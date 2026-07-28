import AppKit
import Carbon
@preconcurrency import InputMethodKit
import VibeVoiceInputShared

/// IMK controller. Key routing follows Squirrel's `SquirrelInputController`:
/// translate macOS events → X11 keysyms + IBus modifiers, feed librime, then
/// refresh UI from the engine context.
///
/// Exception: when the candidate bar is showing a Core ML–reranked page, Space /
/// digits / ←→ / Tab / Shift+Tab address that display order (mapped back via
/// `engineIndex`). All other keys — including Shift ascii toggle, punctuation,
/// Escape, Return, paging — go through librime unchanged.
final class InputMethodController: IMKInputController {
    private let bridge = InputMethodBridgeStore()
    private let rime = VibeVoiceRimeEngine()
    /// Second librime session shared with the same runtime; used only to look
    /// up words for adjacent-swap–corrected pinyin without touching composition.
    private let rimeLookup = VibeVoiceRimeEngine()
    private let ranker = CandidateRankerFactory.make()
    private var bridgeTimer: Timer?
    private var deliveredRequestID: UUID?
    private var composing = ""
    private var displayed: [RimeCandidate] = []
    /// Absolute index into `displayed`.
    private var highlight = 0
    /// First visible index; one screen shows at most `pageSize` rows (digits 1–9).
    private var pageStart = 0
    private let pageSize = 9
    private var lastPageNumber = 0
    private var documentContext = ""
    private var sessionContext = ""
    /// True when librime reports no further engine pages after the current one.
    private var rimeIsLastPage = true
    private var rimePageNumber = 0
    /// Squirrel tracks the previous modifier mask so flagsChanged can emit
    /// press / release key events for ascii_composer and key_binder.
    private var lastModifiers: NSEvent.ModifierFlags = []
    /// Last known ascii_mode; flipped transitions play the 中 ↔ EN HUD.
    private var lastAsciiMode = false
    private var asciiModeInitialized = false

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        PinyinLexicon.shared.ensureLoaded()
        ExternalLexicon.shared.ensureLoaded()
        bridgeTimer = Timer.scheduledTimer(
            timeInterval: 0.15, target: self, selector: #selector(pollBridge),
            userInfo: nil, repeats: true
        )
    }

    deinit { bridgeTimer?.invalidate() }

    /// IMK only delivers keyDown by default; Shift / Caps Lock arrive as flagsChanged.
    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask([.keyDown, .flagsChanged]).rawValue)
    }

    @objc private func pollBridge() {
        guard let state = bridge.load(), state.status == .ready, state.isFresh(),
              state.requestID != deliveredRequestID, !state.text.isEmpty else { return }
        insertCommitted(state.text, client: client())
        deliveredRequestID = state.requestID
        bridge.markConsumed(state)
    }

    // MARK: - Key handling (Squirrel-style)

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        let modifiers = event.modifierFlags
        let changes = lastModifiers.symmetricDifference(modifiers)
        var handled = false

        switch event.type {
        case .flagsChanged:
            handled = handleFlagsChanged(
                event, modifiers: modifiers, changes: changes, client: sender
            )

        case .keyDown:
            // Let client apps handle Command shortcuts (Squirrel).
            if modifiers.contains(.command) { break }
            handled = handleKeyDown(event, modifiers: modifiers, client: sender)

        default:
            break
        }
        return handled
    }

    /// Port of Squirrel's `.flagsChanged` branch: Caps Lock, Shift, Control,
    /// Option, Command press/release → librime (ascii_composer switch keys).
    private func handleFlagsChanged(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        changes: NSEvent.ModifierFlags,
        client sender: Any!
    ) -> Bool {
        if lastModifiers == modifiers {
            return true
        }
        guard let rime else {
            lastModifiers = modifiers
            return false
        }

        var rimeModifiers = RimeKeycode.osxModifiersToRime(modifiers: modifiers)
        var keyCode = event.keyCode
        if !RimeKeycode.modifierKeycodes.contains(keyCode) {
            guard let inferred = RimeKeycode.inferModifierKeycode(from: changes) else {
                lastModifiers = modifiers
                rimeUpdate(client: sender)
                return true
            }
            keyCode = inferred
        }
        let rimeKeycode = RimeKeycode.osxKeycodeToRime(
            keycode: keyCode, keychar: nil, shift: false, caps: false
        )

        if changes.contains(.capsLock) {
            // Rime expects XK_Caps_Lock before the lock mask changes;
            // NSFlagsChanged has already applied it.
            rimeModifiers ^= RimeKeycode.lockMask
            _ = processKey(
                rimeKeycode, modifiers: rimeModifiers, engine: rime, client: sender
            )
        }

        // Process releases first — some modifier releases arrive with the next keydown.
        var buffer: [(keycode: UInt32, modifier: UInt32)] = []
        for flag in [NSEvent.ModifierFlags.shift, .control, .option, .command]
        where changes.contains(flag) {
            if modifiers.contains(flag) {
                buffer.append((keycode: rimeKeycode, modifier: rimeModifiers))
            } else {
                buffer.insert(
                    (keycode: rimeKeycode, modifier: rimeModifiers | RimeKeycode.releaseMask),
                    at: 0
                )
            }
        }
        for entry in buffer {
            _ = processKey(
                entry.keycode, modifiers: entry.modifier, engine: rime, client: sender
            )
        }

        lastModifiers = modifiers
        rimeUpdate(client: sender)
        // Modifier-only events are not typed into the client (Squirrel returns false).
        return false
    }

    private func handleKeyDown(
        _ event: NSEvent,
        modifiers: NSEvent.ModifierFlags,
        client sender: Any!
    ) -> Bool {
        guard let rime else { return false }

        // Candidate-bar overrides: Core ML reranking changes display order, so
        // Space / digits / ←→ / Tab / Shift+Tab / ↑↓ must address `displayed`,
        // not librime's page.
        if !displayed.isEmpty {
            let keyCode = Int(event.keyCode)
            switch keyCode {
            case kVK_Space:
                return commitHighlighted(client: sender)
            case kVK_LeftArrow:
                return moveHighlight(by: -1)
            case kVK_RightArrow:
                return moveHighlight(by: 1)
            case kVK_Tab:
                return cycleHighlightWithTab(event: event, modifiers: modifiers)
            case kVK_UpArrow:
                return changeCandidatePage(by: -1, client: sender)
            case kVK_DownArrow:
                return changeCandidatePage(by: 1, client: sender)
            default:
                break
            }
            let chars = event.charactersIgnoringModifiers ?? event.characters ?? ""
            // Some clients deliver Tab as a character without a stable keyCode path.
            if chars == "\t" {
                return cycleHighlightWithTab(event: event, modifiers: modifiers)
            }
            if let digit = digitSelectionIndex(from: chars)
                ?? digitSelectionIndex(keyCode: keyCode) {
                let absolute = pageStart + digit
                if displayed.indices.contains(absolute) {
                    return commitCandidate(at: absolute, client: sender)
                }
            }
        }

        // Squirrel character selection for non-ASCII / shifted punctuation.
        // Special keys (Escape, arrows, F-keys, …) resolve from keycode alone.
        var keyChars = event.charactersIgnoringModifiers
        let capitalModifiers = modifiers.isSubset(of: [.shift, .capsLock])
        if let code = keyChars?.first,
           (capitalModifiers && !code.isLetter) || (!capitalModifiers && !code.isASCII) {
            keyChars = event.characters
        }
        let char = keyChars?.first

        let rimeKeycode = RimeKeycode.osxKeycodeToRime(
            keycode: event.keyCode,
            keychar: char,
            shift: modifiers.contains(.shift),
            caps: modifiers.contains(.capsLock)
        )
        guard rimeKeycode != 0, rimeKeycode != 0xffffff else { return false }

        let rimeModifiers = RimeKeycode.osxModifiersToRime(modifiers: modifiers)
        let handled = processKey(
            rimeKeycode, modifiers: rimeModifiers, engine: rime, client: sender
        )
        rimeUpdate(client: sender)
        return handled
    }

    private func processKey(
        _ keycode: UInt32,
        modifiers: UInt32,
        engine: VibeVoiceRimeEngine,
        client sender: Any!
    ) -> Bool {
        let result = engine.process(keycode: keycode, modifiers: modifiers)
        if let commit = result.commit {
            insertCommitted(commit, client: sender)
        }
        return result.handled
    }

    /// Consume commit text (already handled in processKey) and refresh preedit /
    /// candidate bar from librime context — Squirrel's `rimeUpdate`.
    private func rimeUpdate(client sender: Any!) {
        refresh(client: sender)
        presentModeSwitchIfNeeded(client: sender)
    }

    /// Show the caret-anchored 中 ↔ EN tag animation whenever ascii_mode flips.
    private func presentModeSwitchIfNeeded(client sender: Any!) {
        guard let rime else { return }
        let now = rime.isAsciiMode
        if !asciiModeInitialized {
            lastAsciiMode = now
            asciiModeInitialized = true
            return
        }
        guard now != lastAsciiMode else { return }
        lastAsciiMode = now
        let anchor = Self.insertionRect(from: sender)
        MainActor.assumeIsolated {
            ModeSwitchHUD.shared.play(toEnglish: now, anchor: anchor)
        }
    }

    private func digitSelectionIndex(from chars: String) -> Int? {
        guard chars.count == 1, let digit = Int(chars), (1...9).contains(digit) else { return nil }
        return digit - 1
    }

    private func digitSelectionIndex(keyCode: Int) -> Int? {
        switch keyCode {
        case kVK_ANSI_1, kVK_ANSI_Keypad1: return 0
        case kVK_ANSI_2, kVK_ANSI_Keypad2: return 1
        case kVK_ANSI_3, kVK_ANSI_Keypad3: return 2
        case kVK_ANSI_4, kVK_ANSI_Keypad4: return 3
        case kVK_ANSI_5, kVK_ANSI_Keypad5: return 4
        case kVK_ANSI_6, kVK_ANSI_Keypad6: return 5
        case kVK_ANSI_7, kVK_ANSI_Keypad7: return 6
        case kVK_ANSI_8, kVK_ANSI_Keypad8: return 7
        case kVK_ANSI_9, kVK_ANSI_Keypad9: return 8
        default: return nil
        }
    }

    /// Tab / Shift+Tab candidate cycling. Wraps across the visible page and onto
    /// the next/previous page when needed so the key always produces feedback.
    private func cycleHighlightWithTab(event: NSEvent, modifiers: NSEvent.ModifierFlags) -> Bool {
        let backward = modifiers.contains(.shift)
            && !modifiers.contains(.control)
            && !modifiers.contains(.option)
            && !modifiers.contains(.command)
        return moveHighlight(by: backward ? -1 : 1, wrap: true)
    }

    /// AppKit clients (and some Electron paths) deliver Tab as `insertTab:` /
    /// `insertBacktab:` instead of a keyDown NSEvent. Handle both.
    override func didCommand(by aSelector: Selector!, client sender: Any!) -> Bool {
        guard !displayed.isEmpty, let aSelector else { return false }
        if aSelector == #selector(NSResponder.insertTab(_:)) {
            return moveHighlight(by: 1, wrap: true)
        }
        if aSelector == #selector(NSResponder.insertBacktab(_:)) {
            return moveHighlight(by: -1, wrap: true)
        }
        return false
    }

    private func moveHighlight(by delta: Int, wrap: Bool = false) -> Bool {
        guard !displayed.isEmpty else { return true }
        let pageEnd = min(pageStart + pageSize, displayed.count) - 1
        let next = highlight + delta
        if next < pageStart {
            // Cross to previous page if any.
            if pageStart > 0 {
                pageStart = max(0, pageStart - pageSize)
                highlight = min(pageStart + pageSize - 1, displayed.count - 1)
            } else if wrap {
                // Wrap to the last candidate on the last page.
                let last = displayed.count - 1
                pageStart = (last / pageSize) * pageSize
                highlight = last
            } else {
                highlight = pageStart
            }
        } else if next > pageEnd {
            if pageEnd + 1 < displayed.count {
                pageStart = pageEnd + 1
                highlight = pageStart
            } else if wrap {
                pageStart = 0
                highlight = 0
            } else {
                highlight = pageEnd
            }
        } else {
            highlight = next
        }
        showCandidates(client: client())
        return true
    }

    /// ↑ / ↓ flip the on-screen page (≤9). At the ends, ask librime for another page.
    private func changeCandidatePage(by delta: Int, client sender: Any!) -> Bool {
        guard !displayed.isEmpty else { return true }
        if delta > 0 {
            let nextStart = pageStart + pageSize
            if nextStart < displayed.count {
                pageStart = nextStart
                highlight = pageStart
                showCandidates(client: sender)
                return true
            }
            if !rimeIsLastPage, let rime {
                let key = RimeKeycode.osxKeycodeToRime(
                    keycode: UInt16(kVK_PageDown), keychar: nil, shift: false, caps: false
                )
                _ = processKey(key, modifiers: 0, engine: rime, client: sender)
                rimeUpdate(client: sender)
                return true
            }
            return true
        } else {
            if pageStart > 0 {
                pageStart = max(0, pageStart - pageSize)
                highlight = pageStart
                showCandidates(client: sender)
                return true
            }
            if rimePageNumber > 0, let rime {
                let key = RimeKeycode.osxKeycodeToRime(
                    keycode: UInt16(kVK_PageUp), keychar: nil, shift: false, caps: false
                )
                _ = processKey(key, modifiers: 0, engine: rime, client: sender)
                rimeUpdate(client: sender)
                return true
            }
            return true
        }
    }

    private var visibleSlice: ArraySlice<RimeCandidate> {
        guard !displayed.isEmpty else { return [] }
        let end = min(pageStart + pageSize, displayed.count)
        guard pageStart < end else { return [] }
        return displayed[pageStart..<end]
    }

    // MARK: - Composition state

    private func refresh(client sender: Any!) {
        guard let rime else { return }
        let snapshot = rime.snapshot()
        let wasComposing = !composing.isEmpty
        let pageChanged = snapshot.pageNumber != lastPageNumber
        lastPageNumber = snapshot.pageNumber
        rimePageNumber = snapshot.pageNumber
        rimeIsLastPage = snapshot.isLastPage
        composing = snapshot.preedit

        if composing.isEmpty {
            displayed = []
            highlight = 0
            pageStart = 0
            documentContext = ""
            (sender as? IMKTextInput)?.setMarkedText(
                "",
                selectionRange: NSRange(location: 0, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            hideCandidates()
            return
        }
        if !wasComposing || pageChanged {
            if !wasComposing {
                documentContext = PredictionContext.mergeContext(
                    preceding: Self.precedingText(from: sender),
                    session: sessionContext
                )
            }
            highlight = 0
            pageStart = 0
        }
        let committedPrefix = PredictionContext.committedPrefix(fromPreedit: composing)
        let afterTypo = Self.mergeTypoFixCandidates(
            engineCandidates: snapshot.candidates,
            rawInput: rime.rawInput,
            asciiMode: rime.isAsciiMode,
            lookup: { [rimeLookup] code in
                rimeLookup?.lookupCandidates(forPinyin: code) ?? []
            }
        )
        let merged = Self.mergeReasoningCandidates(
            engineCandidates: afterTypo,
            rawInput: rime.rawInput,
            documentContext: documentContext,
            asciiMode: rime.isAsciiMode
        )
        let ranked = ranker.rank(PredictionContext(
            preedit: composing,
            committedPrefix: committedPrefix,
            documentContext: documentContext,
            candidates: merged
        ))
        // Pin synthesised reasoning / typo-fix rows at the front so the
        // Core ML scorer cannot bury the one-shot mixed line under Rime crumbs.
        displayed = Self.pinSyntheticCandidates(ranked)
        if highlight >= displayed.count {
            highlight = max(displayed.count - 1, 0)
        }
        // Keep the highlighted row on-screen (≤9 per page).
        if highlight < pageStart || highlight >= pageStart + pageSize {
            pageStart = (highlight / pageSize) * pageSize
        }
        if pageStart >= displayed.count, !displayed.isEmpty {
            pageStart = (displayed.count - 1) / pageSize * pageSize
        }
        (sender as? IMKTextInput)?.setMarkedText(
            composing,
            selectionRange: NSRange(location: composing.count, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        showCandidates(client: sender)
    }

    private func showCandidates(client sender: Any!) {
        let slice = Array(visibleSlice)
        let texts = slice.map(\.text)
        let badges: [CandidateBadge?] = slice.map { candidate in
            switch candidate.source {
            case ReasoningCandidate.source:
                if candidate.comment == "fuzzy" {
                    return .fuzzyAccent
                }
                return .reasoning
            case PinyinTypoCorrector.typoFixSource:
                return .typoFix
            default:
                return nil
            }
        }
        let rankerStatus: CandidateStatusKind = {
            switch ranker.status {
            case .ready:
                return .coreML
            case .unavailable:
                return .rime
            case .loading:
                return .loading
            case .disabled:
                return .learning
            }
        }()
        let selected = max(0, highlight - pageStart)
        let hasPrev = pageStart > 0 || rimePageNumber > 0
        let hasNext = pageStart + pageSize < displayed.count || !rimeIsLastPage
        let anchor = Self.insertionRect(from: sender)
        MainActor.assumeIsolated {
            guard !texts.isEmpty else {
                CandidateBarWindow.shared.hide()
                return
            }
            CandidateBarWindow.shared.show(
                candidates: texts,
                highlight: selected,
                anchor: anchor,
                badges: badges,
                status: rankerStatus,
                hasPreviousPage: hasPrev,
                hasNextPage: hasNext
            )
        }
    }

    private func hideCandidates() {
        MainActor.assumeIsolated { CandidateBarWindow.shared.hide() }
    }

    private func clearUI(client sender: Any!) {
        composing = ""
        displayed = []
        highlight = 0
        pageStart = 0
        documentContext = ""
        (sender as? IMKTextInput)?.setMarkedText(
            "",
            selectionRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        hideCandidates()
    }

    override func activateServer(_ sender: Any!) {
        // Prefer a stable US-QWERTY physical layout so keycodes match Squirrel /
        // librime expectations regardless of the system input source order.
        (sender as? IMKTextInput)?.overrideKeyboard(withKeyboardNamed: "com.apple.keylayout.ABC")
        super.activateServer(sender)
    }

    override func deactivateServer(_ sender: Any!) {
        hideCandidates()
        commitComposition(sender)
        super.deactivateServer(sender)
    }

    /// Squirrel commits the raw input buffer on force-commit (focus loss, etc.).
    override func commitComposition(_ sender: Any!) {
        guard let rime else {
            clearUI(client: sender)
            return
        }
        if !displayed.isEmpty {
            _ = commitHighlighted(client: sender)
            if composing.isEmpty { return }
        }
        let raw = rime.rawInput
        if !raw.isEmpty {
            insertCommitted(raw, client: sender)
        } else if !composing.isEmpty {
            insertCommitted(composing, client: sender)
        }
        rime.clear()
        clearUI(client: sender)
    }

    private func commitHighlighted(client sender: Any!) -> Bool {
        guard !composing.isEmpty else { return false }
        guard !displayed.isEmpty else {
            if let flushed = rime?.commitComposition() {
                insertCommitted(flushed, client: sender)
            } else {
                insertCommitted(composing, client: sender)
                rime?.clear()
            }
            refresh(client: sender)
            return true
        }
        return commitCandidate(at: highlight, client: sender)
    }

    private func commitCandidate(at index: Int, client sender: Any!) -> Bool {
        guard displayed.indices.contains(index) else { return false }
        let candidate = displayed[index]
        let committedPrefix = PredictionContext.committedPrefix(fromPreedit: composing)
        ranker.record(candidate, context: PredictionContext(
            preedit: composing,
            committedPrefix: committedPrefix,
            documentContext: documentContext,
            candidates: displayed
        ))

        // Prefer a same-text Rime peer so librime can keep unused syllables
        // after a prefix confirm (合成行没有 engineIndex，直接 clear 会吞掉后半段).
        let rimePeer = displayed.first {
            $0.text == candidate.text && $0.engineIndex >= 0
                && $0.source != PinyinTypoCorrector.typoFixSource
                && $0.source != ReasoningCandidate.source
        }
        let selectable = rimePeer ?? candidate
        let rawBefore = rime?.rawInput ?? ""

        let isSynthetic = selectable.source == PinyinTypoCorrector.typoFixSource
            || selectable.source == ReasoningCandidate.source
            || selectable.engineIndex < 0

        if isSynthetic {
            return commitTextKeepingRemainder(
                selectable.text,
                rawBefore: rawBefore,
                client: sender
            )
        }

        guard let rime else {
            return commitTextKeepingRemainder(
                selectable.text,
                rawBefore: rawBefore,
                client: sender
            )
        }
        guard let outcome = rime.selectCandidate(selectable.engineIndex) else { return false }
        let flushedText: String?
        if case .flushed(let text) = outcome {
            insertCommitted(text, client: sender)
            flushedText = text
        } else {
            flushedText = nil
        }
        highlight = 0
        pageStart = 0
        refresh(client: sender)

        // Safety net: if librime emptied the composition despite a shorter
        // selection, re-feed the unused syllables so selection can continue.
        if composing.isEmpty {
            let consumed = flushedText ?? selectable.text
            if let remaining = PartialPinyinCommit.remainingCode(
                afterCommitting: consumed,
                rawInput: rawBefore
            ), !remaining.isEmpty {
                feedLatinCode(remaining, client: sender)
            }
        }
        return true
    }

    /// Insert confirmed text, then restore any unused pinyin into a fresh
    /// composition instead of wiping the whole session.
    private func commitTextKeepingRemainder(
        _ text: String,
        rawBefore: String,
        client sender: Any!
    ) -> Bool {
        insertCommitted(text, client: sender)
        rime?.clear()
        if let remaining = PartialPinyinCommit.remainingCode(
            afterCommitting: text,
            rawInput: rawBefore
        ), !remaining.isEmpty {
            feedLatinCode(remaining, client: sender)
        } else {
            clearUI(client: sender)
        }
        return true
    }

    private func feedLatinCode(_ latin: String, client sender: Any!) {
        guard let rime else {
            clearUI(client: sender)
            return
        }
        for character in latin.lowercased() where character.isASCII && character.isLetter {
            guard let value = character.unicodeScalars.first?.value else { continue }
            _ = rime.process(keycode: value, modifiers: 0)
        }
        highlight = 0
        pageStart = 0
        refresh(client: sender)
        if composing.isEmpty {
            clearUI(client: sender)
        }
    }

    /// When raw Latin input fails full syllable segmentation, try adjacent
    /// letter swap and Cantonese-friendly fuzzy recoveries, then look up words.
    /// Preedit stays as typed.
    static func mergeTypoFixCandidates(
        engineCandidates: [RimeCandidate],
        rawInput: String,
        asciiMode: Bool,
        lookup: (String) -> [RimeCandidate]
    ) -> [RimeCandidate] {
        guard !asciiMode else { return engineCandidates }
        let latin = PinyinTypoCorrector.latinCode(from: rawInput)
        var codes: [String] = []
        if let corrected = PinyinTypoCorrector.correctAdjacentSwap(latin) {
            codes.append(corrected)
        }
        if PinyinFuzzyCorrector.isEnabled() {
            for recovered in PinyinFuzzyCorrector.recoverUnsegmentable(latin) where !codes.contains(recovered) {
                codes.append(recovered)
            }
        }
        guard !codes.isEmpty else { return engineCandidates }

        var recovered: [RimeCandidate] = []
        var seenText = Set<String>()
        for code in codes.prefix(3) {
            for candidate in lookup(code) {
                guard seenText.insert(candidate.text).inserted else { continue }
                recovered.append(RimeCandidate(
                    text: candidate.text,
                    comment: "↔\(code)",
                    engineIndex: -1,
                    rawWeight: candidate.rawWeight,
                    source: PinyinTypoCorrector.typoFixSource
                ))
            }
        }
        guard !recovered.isEmpty else { return engineCandidates }
        if engineCandidates.isEmpty { return recovered }
        // Prefer Rime rows when text collides so partial select keeps remainder.
        return PartialPinyinCommit.preferRimeRows(recovered + engineCandidates)
    }

    /// Keep synthesised rows first after Core ML rerank.
    static func pinSyntheticCandidates(_ candidates: [RimeCandidate]) -> [RimeCandidate] {
        let syntheticSources: Set<String> = [
            ReasoningCandidate.source,
            PinyinTypoCorrector.typoFixSource,
        ]
        let pinned = candidates.filter { syntheticSources.contains($0.source ?? "") }
        let rest = candidates.filter { !syntheticSources.contains($0.source ?? "") }
        return pinned + rest
    }

    /// Inject a full-line composition from the mixed reasoning engine.
    /// Only high-confidence (or medium + mixed/fuzzy) rows go first — low-confidence
    /// guesses stay out so they don't fight Rime and force extra attention.
    static func mergeReasoningCandidates(
        engineCandidates: [RimeCandidate],
        rawInput: String,
        documentContext: String,
        asciiMode: Bool,
        style: MixedOutputStyle = MixedOutputStyle.load()
    ) -> [RimeCandidate] {
        guard !asciiMode else { return engineCandidates }
        // Ensure dictionaries are warm before the first composition attempt.
        _ = PinyinLexicon.shared.prepareForUse()
        ExternalLexicon.shared.ensureLoaded()
        guard let composition = MixedTokenAnalyzer.compose(
            rawInput: rawInput,
            documentContext: documentContext,
            style: style
        ) else {
            return engineCandidates
        }

        // Align with Rime when the page already has a better full phrase
        // (魔法帮 composer vs 魔法棒 on the Rime page).
        let reconciled = ReasoningRimeReconciler.reconcile(
            composed: composition.text,
            rimeCandidates: engineCandidates
        )
        let finalText = reconciled.text
        if engineCandidates.first?.text == finalText {
            return engineCandidates
        }

        let isMixed = composition.hasProperNoun || composition.hasEnglish
        let worthShowing: Bool
        switch composition.confidence {
        case .high:
            worthShowing = true
        case .medium:
            // Medium only when it clearly adds value (English mix, fuzzy, or Rime peer).
            worthShowing = isMixed || composition.fuzzyEdits > 0
                || reconciled.usedRimePeer || finalText.count >= 4
        case .low:
            worthShowing = isMixed || reconciled.usedRimePeer
        }
        guard worthShowing else { return engineCandidates }

        // If we only "won" by copying a Rime peer, just pin that Rime row —
        // don't invent a duplicate synthetic with a wand badge unless mixed/fuzzy.
        if reconciled.usedRimePeer,
           !isMixed,
           composition.fuzzyEdits == 0,
           let peerIndex = engineCandidates.firstIndex(where: { $0.text == finalText }) {
            var merged = engineCandidates
            let peer = merged.remove(at: peerIndex)
            merged.insert(peer, at: 0)
            var seen = Set<String>()
            return merged.filter { seen.insert($0.text).inserted }
        }

        let synthetic = RimeCandidate(
            text: finalText,
            comment: isMixed ? "mixed" : (composition.fuzzyEdits > 0 ? "fuzzy" : "reason"),
            engineIndex: -1,
            rawWeight: composition.score,
            source: ReasoningCandidate.source
        )
        if engineCandidates.isEmpty {
            return [synthetic]
        }
        var merged = engineCandidates
        switch composition.confidence {
        case .high:
            merged.insert(synthetic, at: 0)
        case .medium:
            if isMixed || composition.fuzzyEdits > 0 || reconciled.usedRimePeer {
                merged.insert(synthetic, at: 0)
            } else {
                merged.insert(synthetic, at: min(1, merged.count))
            }
        case .low:
            merged.insert(synthetic, at: min(1, merged.count))
        }
        // Deduplicate by text; keep Rime's engineIndex when it matches a synthetic.
        return PartialPinyinCommit.preferRimeRows(merged)
    }

    private func insertCommitted(_ text: String, client sender: Any!) {
        guard !text.isEmpty else { return }
        (sender as? IMKTextInput)?.insertText(
            text, replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        appendSessionContext(text)
    }

    private func appendSessionContext(_ text: String) {
        guard !IsSecureEventInputEnabled(), !text.isEmpty else { return }
        sessionContext += text
        let limit = PredictionContext.contextCharacterLimit * 2
        if sessionContext.count > limit {
            sessionContext = String(sessionContext.suffix(limit))
        }
    }

    private static func insertionRect(from sender: Any!) -> NSRect {
        guard let client = sender as? IMKTextInput else {
            return NSRect(x: 80, y: 80, width: 1, height: 16)
        }
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        if rect.width < 1 || rect.height < 1 {
            return NSRect(x: 80, y: 80, width: 1, height: 16)
        }
        return rect
    }

    private static func precedingText(from sender: Any!) -> String {
        guard !IsSecureEventInputEnabled(), let client = sender as? IMKTextInput else { return "" }
        let cursor = client.selectedRange().location
        guard cursor != NSNotFound, cursor > 0 else { return "" }
        let length = min(cursor, PredictionContext.contextCharacterLimit)
        let range = NSRange(location: cursor - length, length: length)
        return client.attributedSubstring(from: range)?.string ?? ""
    }

    @objc func toggleVoice(_ sender: Any?) {
        if let state = bridge.load(), state.status == .requested || state.status == .recording {
            _ = bridge.update(.stopRequested, from: state)
        } else {
            _ = bridge.request()
        }
    }

    @objc func showHelp(_ sender: Any?) {
        MainActor.assumeIsolated { InputMethodHelpPanel.shared.show() }
    }

    @objc func openMainApp(_ sender: Any?) {
        let bundleID = "app.vibevoice.oss.macos"
        let config = NSWorkspace.OpenConfiguration()
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }
        let fallback = URL(fileURLWithPath: "/Applications/Vibe Voice OSS.app")
        if FileManager.default.fileExists(atPath: fallback.path) {
            NSWorkspace.shared.openApplication(at: fallback, configuration: config)
        }
    }

    @objc func openLogsFolder(_ sender: Any?) {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VibeVoiceOSS/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc func openUserLexicon(_ sender: Any?) {
        let url = ExternalLexicon.projectLexiconURL().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
    }

    @objc func openDocumentation(_ sender: Any?) {
        guard let url = URL(string: "https://github.com/jeffincn/vibe-voice-oss") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func showAbout(_ sender: Any?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        let alert = NSAlert()
        alert.messageText = "Vibe Type"
        alert.informativeText = chinese
            ? "版本 \(version)（\(build)）\nVibe Voice OSS 拼音输入法\n支持中英混输、智能组句与语音输入。"
            : "Version \(version) (\(build))\nPinyin input method for Vibe Voice OSS.\nMixed Chinese/English, smart phrases, and voice input."
        alert.alertStyle = .informational
        alert.addButton(withTitle: chinese ? "好" : "OK")
        alert.runModal()
    }

    override func menu() -> NSMenu! {
        let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") == true
        let menu = NSMenu(title: "Vibe Type")

        func item(_ title: String, _ action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            return item
        }

        menu.addItem(item(chinese ? "语音输入" : "Voice Input", #selector(toggleVoice(_:))))
        menu.addItem(.separator())
        menu.addItem(item(chinese ? "快捷键说明…" : "Keyboard Shortcuts…", #selector(showHelp(_:))))
        menu.addItem(item(chinese ? "打开主应用…" : "Open Main App…", #selector(openMainApp(_:))))
        menu.addItem(item(chinese ? "日志…" : "Logs…", #selector(openLogsFolder(_:))))
        menu.addItem(item(chinese ? "用户词典…" : "User Lexicon…", #selector(openUserLexicon(_:))))
        menu.addItem(.separator())
        menu.addItem(item(
            chinese ? "使用说明（GitHub）…" : "Documentation (GitHub)…",
            #selector(openDocumentation(_:))
        ))
        menu.addItem(item(chinese ? "关于 Vibe Type" : "About Vibe Type", #selector(showAbout(_:))))
        return menu
    }
}

typealias VibeVoiceInputController = InputMethodController
