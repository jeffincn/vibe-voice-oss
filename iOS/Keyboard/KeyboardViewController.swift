import UIKit

final class KeyboardViewController: UIInputViewController {
    /// The Darwin signal from the containing app is best-effort and coalescing,
    /// so a slow timer backs it up. It replaces the 0.4s poll this controller
    /// used to run for as long as the keyboard was on screen.
    private static let bridgeBackstopInterval: TimeInterval = 2
    /// Tight fit above the home-indicator inset: chrome + three letter rows +
    /// utility row. Extra slack under the keys was what made the dock look empty.
    private static let contentHeight: CGFloat = 318
    private static let compositionRowHeight: CGFloat = 38
    private static let candidateRowHeight: CGFloat = 54
    /// Near-square on a phone-width QWERTY row (~40pt wide keys). Fill-equally
    /// against a taller keyboard was what elongated every cap.
    private static let keyRowHeight: CGFloat = 46
    private static let keyRowSpacing: CGFloat = 7
    private static let accent = UIColor(named: "AccentColor") ?? .systemIndigo
    private static let shiftLockInterval: TimeInterval = 0.35

    private var engine: RimeEngine = PrototypeRimeEngine()
    private var candidateRanker: CandidateRanker = PassthroughCandidateRanker(persistLearning: false)
    private let restrictedRanker = PassthroughCandidateRanker(persistLearning: false)
    private var privacyState = KeyboardPrivacyState(hasFullAccess: false, isSecureTextEntry: false)
    private var rankedCandidates: [RimeCandidate] = []
    private var rankedCandidateIndices: [Int] = []
    private var rankedPreedit = ""
    private var rankRequestID = UUID()
    /// Non-nil when librime failed to start and the prototype engine is standing
    /// in with its ten-word lexicon.
    private var rimeDegradedReason: String?
    private let bridge = VoiceBridgeStore()
    private var language: KeyboardLanguage = .chinese
    private var plane: KeyboardPlane = .letters
    private var shift: KeyboardShift = .off
    private var lastShiftTap: Date?
    private var voiceMode: VoiceOutputMode = .polished
    private var lastInsertedRequestID: UUID?
    private var bridgeTimer: Timer?
    private var bridgeWatcher: VoiceBridgeWatcher?
    /// A finished transcript that belongs to a different text field. It waits
    /// here until the user goes back to that field or asks for it explicitly.
    private var pendingResult: VoiceBridgeState?
    /// The host text field the composition currently belongs to, cached from
    /// `UITextDocumentProxy.documentIdentifier`.
    private var currentDocumentID: UUID?
    /// The host channel last sampled, so a fingerprint is logged when it
    /// changes rather than on every keystroke.
    private var hostChannel: HostChannel?
    /// Set while we edit the document ourselves, so the change callbacks that
    /// follow are not mistaken for the user moving the caret.
    private var isPerformingOwnEdit = false

    private lazy var heightConstraint: NSLayoutConstraint = {
        let constraint = view.heightAnchor.constraint(equalToConstant: Self.contentHeight)
        // The system installs its own required height on the input view. A
        // required constraint of ours would conflict with it and one of the two
        // gets broken at runtime, so stay just below required.
        constraint.priority = UILayoutPriority(999)
        return constraint
    }()

    private let preeditLabel = UILabel()
    private let candidateStack = UIStackView()
    private let candidateScroll = UIScrollView()
    private let expandCandidatesButton = UIButton(type: .system)
    private let clearButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let compositionRow = UIStackView()
    private let candidateRow = UIStackView()
    private let keysZone = UIStackView()
    private let keyRowsStack = UIStackView()
    private let planeButton = UIButton(type: .system)
    private let emojiButton = UIButton(type: .system)
    private let spaceButton = UIButton(type: .system)
    private let returnButton = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)
    private let keyboardRoot = UIStackView()
    private let expandedPanel = ExpandedCandidatesPanel()
    private var isCandidatesExpanded = false
    /// Items shown in the expanded sheet. `engineIndex == nil` means "commit the
    /// raw Latin preedit", which is how free English typing stays selectable.
    private var expandedItems: [BarCandidate] = []
    private var expandedCandidates: [RimeCandidate] = []
    private var utilityRow: UIView!

    override func viewDidLoad() {
        super.viewDidLoad()
        MobileLog.info(.lifecycle, "keyboard.loaded", [
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "fullAccess": String(hasFullAccess),
            "storage": DiagnosticStore.shared.storageDescription,
        ])
        refreshPrivacyState()
        voiceMode = bridge.load().mode
        // Do not synchronously initialise librime here. On a physical device
        // the first session may open/deploy a large dictionary and block the
        // keyboard extension's main thread long enough for iOS to report it as
        // hung. The prototype engine keeps the UI responsive while Rime loads.
        loadRimeEngineInBackground()
        view.backgroundColor = UIColor.systemGray6
        // Set rather than inherited: an extension's window is not the app's, so
        // the global accent colour does not reach the keys on its own.
        view.tintColor = Self.accent
        configureLayout()
        rebuildKeyRows()
        refreshComposition()
        refreshBridge()
        startBridgeObservation()
    }

    private func loadRimeEngineInBackground() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let result = RimeEngineFactory.makeForKeyboard()
            DispatchQueue.main.async {
                guard let self else { return }
                // Preserve any text entered while Rime was loading. The next
                // key starts a clean Rime session instead of losing input.
                guard !self.engine.snapshot.isComposing else {
                    MobileLog.info(.rime, "engine.swapDeferred", [
                        "reason": "composition in flight",
                    ])
                    return
                }
                self.engine = result.engine
                self.rimeDegradedReason = result.degradedReason
                self.refreshComposition()
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshPrivacyState()
        // Before refreshBridge, which decides whether a finished transcript
        // belongs to this field and needs the document identity to do it.
        refreshHostContext()
        refreshBridge()
        startBridgeObservation()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopBridgeObservation()
    }

    deinit {
        bridgeTimer?.invalidate()
        bridgeWatcher = nil
    }

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        refreshPrivacyState()
        refreshHostContext()
    }

    /// Caches the host document identity and, when it changes, the channel
    /// fingerprint.
    ///
    /// Only called from places where the host is known to be talking to us.
    /// `refreshBridge` runs on a timer and deliberately does not do this: the
    /// host connection can be invalid while iOS restarts PlugInKit, and
    /// touching the proxy then is what produces extension-handshake crashes.
    /// That path reads the values cached here instead.
    private func refreshHostContext() {
        let proxy = textDocumentProxy
        let documentID = hostDocumentIdentifier()
        guard documentID != currentDocumentID || hostChannel == nil else { return }

        let previous = currentDocumentID
        currentDocumentID = documentID
        // Sampling the full channel costs several proxy round trips, so it is
        // tied to the document changing rather than to each keystroke.
        let channel = HostChannel.sample(proxy: proxy, hasFullAccess: hasFullAccess)
        hostChannel = channel

        var fields = channel.fields
        fields["document"] = documentID?.uuidString.prefix(8).lowercased() ?? "none"
        fields["previous"] = previous?.uuidString.prefix(8).lowercased() ?? "none"
        MobileLog.info(.host, "document.attached", fields)
    }

    /// Reads `documentIdentifier` without trusting its declared nullability.
    ///
    /// UIKit declares the property non-null, but the host proxy returns nil
    /// while the extension handshake is incomplete and while iOS is restarting
    /// PlugInKit. Swift then bridges that nil into a non-optional `UUID` and
    /// traps. That is not hypothetical: build 62 died exactly here, on the
    /// first `textDidChange` after being attached — `EXC_BREAKPOINT` inside
    /// `UUID._unconditionallyBridgeFromObjectiveC`, recorded in
    /// `VibeVoiceKeyboard-2026-07-29-141238.ips`.
    ///
    /// Going through key-value coding keeps the result an object all the way
    /// into Swift, so nil stays representable instead of becoming a trap.
    private func hostDocumentIdentifier() -> UUID? {
        let proxy = textDocumentProxy as AnyObject
        let getter = #selector(getter: UITextDocumentProxy.documentIdentifier)
        guard proxy.responds(to: getter) else { return nil }
        return proxy.value(forKey: NSStringFromSelector(getter)) as? UUID
    }

    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        super.selectionWillChange(textInput)
        // The user moved the caret away from where the composition was being
        // built. Committing it now would drop the characters somewhere else.
        guard !isPerformingOwnEdit, engine.snapshot.isComposing else { return }
        engine.reset()
        refreshComposition()
    }

    private func refreshPrivacyState() {
        let next = KeyboardPrivacyState(
            hasFullAccess: hasFullAccess,
            // Custom keyboards are not presented for secure text fields. On
            // iOS 26, querying this proxy property during the extension
            // handshake can trap with EXC_BREAKPOINT, so do not touch the host
            // proxy merely to rediscover a restriction enforced by the system.
            isSecureTextEntry: false
        )
        guard next != privacyState else { return }
        privacyState = next
        candidateRanker = next.allowsEnhancedInference
            ? CandidateRankerFactory.make()
            : restrictedRanker
        // Privacy state stays in Diagnostics only — never on the candidate bar.
    }

    // MARK: - Layout

    private func configureLayout() {
        preeditLabel.font = .preferredFont(forTextStyle: .callout)
        preeditLabel.textColor = Self.accent
        preeditLabel.setContentHuggingPriority(.required, for: .horizontal)

        candidateStack.axis = .horizontal
        candidateStack.spacing = 8
        candidateStack.alignment = .fill

        candidateScroll.showsHorizontalScrollIndicator = false
        candidateScroll.addSubview(candidateStack)
        candidateStack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            candidateStack.leadingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.leadingAnchor),
            candidateStack.trailingAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.trailingAnchor),
            candidateStack.topAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.topAnchor),
            candidateStack.bottomAnchor.constraint(equalTo: candidateScroll.contentLayoutGuide.bottomAnchor),
            candidateStack.heightAnchor.constraint(equalTo: candidateScroll.frameLayoutGuide.heightAnchor),
        ])

        var expandConfig = UIButton.Configuration.plain()
        expandConfig.image = UIImage(systemName: "chevron.down")
        expandConfig.baseForegroundColor = .secondaryLabel
        expandConfig.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        expandCandidatesButton.configuration = expandConfig
        expandCandidatesButton.accessibilityLabel = MobileL10n.t(.candidateExpand)
        expandCandidatesButton.addAction(UIAction { [weak self] _ in
            self?.toggleCandidateExpansion()
        }, for: .touchUpInside)

        clearButton.setTitle(MobileL10n.t(.keyClear), for: .normal)
        clearButton.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        clearButton.setTitleColor(.secondaryLabel, for: .normal)
        clearButton.accessibilityLabel = MobileL10n.t(.keyClear)
        clearButton.setContentHuggingPriority(.required, for: .horizontal)
        clearButton.addAction(UIAction { [weak self] _ in
            self?.clearComposition()
        }, for: .touchUpInside)

        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .right
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        styleVoiceButton()
        voiceButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        voiceButton.addAction(UIAction { [weak self] _ in self?.requestVoice() }, for: .touchUpInside)
        configureVoiceMenu()

        // Two lines again: pinyin on top, candidates underneath. Sharing one
        // strip made long preedits shove the candidates off-screen.
        compositionRow.axis = .horizontal
        compositionRow.spacing = 6
        compositionRow.alignment = .center
        [
            preeditLabel,
            UIView(),
            statusLabel,
            clearButton,
            voiceButton,
        ].forEach(compositionRow.addArrangedSubview)
        compositionRow.heightAnchor.constraint(equalToConstant: Self.compositionRowHeight).isActive = true

        candidateRow.axis = .horizontal
        candidateRow.spacing = 4
        candidateRow.alignment = .fill
        [candidateScroll, expandCandidatesButton].forEach(candidateRow.addArrangedSubview)
        candidateRow.heightAnchor.constraint(equalToConstant: Self.candidateRowHeight).isActive = true

        let chrome = UIStackView(arrangedSubviews: [compositionRow, candidateRow])
        chrome.axis = .vertical
        chrome.spacing = 4

        utilityRow = makeUtilityRow()
        utilityRow.heightAnchor.constraint(equalToConstant: Self.keyRowHeight).isActive = true

        keyRowsStack.axis = .vertical
        keyRowsStack.spacing = Self.keyRowSpacing
        keyRowsStack.distribution = .fillEqually
        keyRowsStack.heightAnchor.constraint(
            equalToConstant: Self.keyRowHeight * 3 + Self.keyRowSpacing * 2
        ).isActive = true

        keysZone.axis = .vertical
        keysZone.spacing = Self.keyRowSpacing
        keysZone.distribution = .fill
        keysZone.addArrangedSubview(keyRowsStack)
        keysZone.addArrangedSubview(utilityRow)

        keyboardRoot.axis = .vertical
        keyboardRoot.spacing = 6
        keyboardRoot.translatesAutoresizingMaskIntoConstraints = false
        [chrome, keysZone].forEach(keyboardRoot.addArrangedSubview)
        view.addSubview(keyboardRoot)

        expandedPanel.isHidden = true
        expandedPanel.translatesAutoresizingMaskIntoConstraints = false
        expandedPanel.onSelect = { [weak self] index in self?.selectExpandedCandidate(at: index) }
        expandedPanel.onCollapse = { [weak self] in self?.setCandidatesExpanded(false) }
        expandedPanel.onDismissKeyboard = { [weak self] in self?.setCandidatesExpanded(false) }
        expandedPanel.onNextKeyboard = { [weak self] in self?.advanceToNextInputMode() }
        view.addSubview(expandedPanel)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            keyboardRoot.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 4),
            keyboardRoot.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -4),
            keyboardRoot.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            keyboardRoot.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -4),

            expandedPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            expandedPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            expandedPanel.topAnchor.constraint(equalTo: view.topAnchor),
            expandedPanel.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            heightConstraint,
        ])
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        heightConstraint.constant = Self.contentHeight + view.safeAreaInsets.bottom
    }

    /// The character rows are rebuilt rather than mutated: switching plane
    /// changes how many keys a row holds, and shift changes every title.
    private func rebuildKeyRows() {
        keyRowsStack.arrangedSubviews.forEach {
            keyRowsStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, keys) in plane.rows.enumerated() {
            keyRowsStack.addArrangedSubview(
                makeKeyRow(keys, inset: plane.isInset(row: index))
            )
        }
        planeButton.configuration?.title = plane.alternateLabel
        planeButton.accessibilityLabel = MobileL10n.t(
            plane == .letters ? .keyNumbersPlane : .keyLettersPlane
        )
    }

    private func makeKeyRow(_ keys: [KeyboardKey], inset: Bool) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Self.keyRowSpacing - 3
        row.distribution = .fill

        var characterKeys: [UIButton] = []
        for key in keys {
            let button = makeButton(for: key)
            if case .character = key {
                characterKeys.append(button)
            } else {
                button.widthAnchor.constraint(equalToConstant: 46).isActive = true
            }
            row.addArrangedSubview(button)
        }
        // Character keys share whatever the modifier keys leave behind, which is
        // what makes a nine-key row line up with a ten-key one.
        if let reference = characterKeys.first {
            for button in characterKeys.dropFirst() {
                button.widthAnchor.constraint(equalTo: reference.widthAnchor).isActive = true
            }
            if inset {
                let leading = UIView()
                let trailing = UIView()
                row.insertArrangedSubview(leading, at: 0)
                row.addArrangedSubview(trailing)
                NSLayoutConstraint.activate([
                    leading.widthAnchor.constraint(equalTo: reference.widthAnchor, multiplier: 0.5),
                    trailing.widthAnchor.constraint(equalTo: leading.widthAnchor),
                ])
            }
        }
        return row
    }

    private func makeButton(for key: KeyboardKey) -> UIButton {
        let button = UIButton(type: .system)
        applyChrome(
            to: button,
            role: chromeRole(for: key),
            title: title(for: key),
            image: image(for: key)
        )
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        button.accessibilityLabel = accessibilityLabel(for: key)
        if case let .character(text) = key {
            button.accessibilityIdentifier = "key.\(text.lowercased())"
        }
        if key == .shift, shift != .off {
            button.configuration?.baseBackgroundColor = .tertiarySystemFill
        }
        button.addAction(UIAction { [weak self] _ in
            self?.handle(key)
        }, for: .touchUpInside)
        return button
    }

    private func title(for key: KeyboardKey) -> String? {
        switch key {
        case let .character(text):
            return shift.isRaised ? text.uppercased() : text
        case .shift, .backspace:
            return nil
        case let .plane(target):
            return target == .symbols ? "#+=" : "123"
        }
    }

    private func image(for key: KeyboardKey) -> UIImage? {
        switch key {
        case .shift:
            let name = shift == .locked ? "capslock.fill" : "shift"
            return UIImage(systemName: name)
        case .backspace:
            return UIImage(systemName: "delete.left")
        default:
            return nil
        }
    }

    private func accessibilityLabel(for key: KeyboardKey) -> String {
        switch key {
        case let .character(text):
            // VoiceOver announces a bare glyph inconsistently across voices.
            return shift.isRaised ? text.uppercased() : text
        case .shift:
            return MobileL10n.t(shift == .locked ? .keyCapsLock : .keyShift)
        case let .plane(target):
            return MobileL10n.t(target == .symbols ? .keySymbolsPlane : .keyNumbersPlane)
        case .backspace:
            return MobileL10n.t(.keyDelete)
        }
    }

    private func makeUtilityRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Self.keyRowSpacing - 3
        row.distribution = .fill

        // System Mandarin keyboard bottom row: 123 | emoji | space | return.
        // No globe (system draws one under the extension) and no 中/英 key
        // (language toggles from a long-press on space).
        applyChrome(to: planeButton, role: .function, title: plane.alternateLabel, image: nil)
        planeButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        planeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            handle(.plane(plane.alternate))
        }, for: .touchUpInside)

        applyChrome(
            to: emojiButton,
            role: .function,
            title: nil,
            image: UIImage(systemName: "face.smiling")
        )
        emojiButton.accessibilityLabel = MobileL10n.t(.keySwitchKeyboard)
        emojiButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        emojiButton.addAction(UIAction { [weak self] _ in
            self?.advanceToNextInputMode()
        }, for: .touchUpInside)

        applyChrome(to: spaceButton, role: .letter, title: nil, image: nil)
        spaceButton.accessibilityLabel = MobileL10n.t(.keySpace)
        spaceButton.accessibilityHint = MobileL10n.t(.keyToggleLanguage)
        spaceButton.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spaceButton.addAction(UIAction { [weak self] _ in self?.handleSpace() }, for: .touchUpInside)
        let spaceLongPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(toggleLanguageFromChrome)
        )
        spaceLongPress.minimumPressDuration = 0.35
        spaceButton.addGestureRecognizer(spaceLongPress)
        refreshSpaceAppearance()

        applyChrome(
            to: returnButton,
            role: .function,
            title: nil,
            image: UIImage(systemName: "return")
        )
        returnButton.accessibilityLabel = MobileL10n.t(.keyNewline)
        returnButton.widthAnchor.constraint(equalToConstant: 52).isActive = true
        // Never put the word "return"/"换行" on this key — it wraps on phone widths.
        returnButton.titleLabel?.numberOfLines = 1
        returnButton.addAction(UIAction { [weak self] _ in self?.handleReturn() }, for: .touchUpInside)

        [planeButton, emojiButton, spaceButton, returnButton]
            .forEach(row.addArrangedSubview)
        return row
    }

    private enum KeyChromeRole {
        case letter
        case function
    }

    private func chromeRole(for key: KeyboardKey) -> KeyChromeRole {
        switch key {
        case .character: return .letter
        case .shift, .plane, .backspace: return .function
        }
    }

    /// Letter keys lift off a white (or dark-elevated) surface; function keys sit
    /// flush in a grey fill so 123 / emoji / return / shift / delete read as modifiers.
    private static let letterKeyFill = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .tertiarySystemBackground : .systemBackground
    }
    private static let functionKeyFill = UIColor.systemGray4

    private func applyChrome(
        to button: UIButton,
        role: KeyChromeRole,
        title: String?,
        image: UIImage?
    ) {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = role == .letter ? Self.letterKeyFill : Self.functionKeyFill
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        // Keep vertical inset modest: large top/bottom padding was stretching the
        // glyph area inside an already-fixed row height and made caps look tall.
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 3, bottom: 6, trailing: 3)
        configuration.title = title
        configuration.image = image
        configuration.imagePadding = 0
        // Prefer shrinking over wrapping — return text wrapping was the failure mode.
        configuration.titleLineBreakMode = .byClipping
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
        button.titleLabel?.numberOfLines = 1
        // On the button's own layer, not the configuration's background: a title
        // change re-applies the configuration and would take the shadow with it.
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOpacity = role == .letter ? 0.14 : 0.08
        button.layer.shadowRadius = 1.2
        button.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    /// System Chinese space bars show a faint 「拼」; English mode stays blank.
    private func refreshSpaceAppearance() {
        var configuration = spaceButton.configuration ?? UIButton.Configuration.filled()
        configuration.baseBackgroundColor = Self.letterKeyFill
        configuration.baseForegroundColor = .tertiaryLabel
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 3, bottom: 6, trailing: 3)
        configuration.image = nil
        if language == .chinese {
            var hint = AttributedString("拼")
            hint.font = .preferredFont(forTextStyle: .footnote)
            hint.foregroundColor = UIColor.tertiaryLabel
            configuration.attributedTitle = hint
        } else {
            configuration.attributedTitle = nil
            configuration.title = nil
        }
        spaceButton.configuration = configuration
        spaceButton.layer.shadowColor = UIColor.black.cgColor
        spaceButton.layer.shadowOpacity = 0.14
        spaceButton.layer.shadowRadius = 1.2
        spaceButton.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    private func styleVoiceButton() {
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(systemName: "mic.fill")
        configuration.baseForegroundColor = Self.accent
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
        voiceButton.configuration = configuration
    }

    // MARK: - Key handling

    private func handle(_ key: KeyboardKey) {
        switch key {
        case let .character(text):
            handleCharacter(text)
        case .shift:
            toggleShift()
        case let .plane(target):
            plane = target
            rebuildKeyRows()
        case .backspace:
            handleBackspace()
        }
    }

    private func handleCharacter(_ text: String) {
        let output = shift.isRaised ? text.uppercased() : text
        defer { consumeOneShotShift() }

        guard language == .chinese,
              output.count == 1,
              let character = output.first,
              character.isASCII else {
            commitPendingComposition()
            insertIntoDocument(output)
            return
        }

        if character.isNumber, selectCandidateByDigit(character) {
            return
        }

        // Only lowercase letters extend composition — same rule as the system
        // Mandarin keyboard. Punctuation, digits, symbols, and uppercase commit
        // immediately so they never linger as a named preedit.
        if character.isLetter, !character.isUppercase {
            apply(engine.process(character: character), fallback: output)
            return
        }

        commitPendingComposition()
        insertIntoDocument(ChinesePunctuation.mapped(character))
    }

    /// Digits pick from the visible candidate page while composing. librime can
    /// be configured to do this, but only through schema keys this project does
    /// not ship, so the keyboard owns the rule.
    private func selectCandidateByDigit(_ digit: Character) -> Bool {
        let snapshot = engine.snapshot
        guard snapshot.isComposing, let value = digit.wholeNumberValue else { return false }
        let index = value == 0 ? 9 : value - 1
        let engineIndex = rankedCandidateIndices.indices.contains(index)
            ? rankedCandidateIndices[index]
            : index
        guard snapshot.candidates.indices.contains(engineIndex) else { return false }
        let outcome = engine.selectCandidate(at: engineIndex)
        guard outcome.handled else { return false }
        MobileLog.info(.rime, "candidate.selected", [
            "display": String(index),
            "engine": String(engineIndex),
            "via": "digit",
            "commitLen": String(outcome.commit?.count ?? 0),
        ])
        apply(outcome, fallback: nil)
        return true
    }

    private func toggleShift() {
        let now = Date()
        if let lastShiftTap, now.timeIntervalSince(lastShiftTap) < Self.shiftLockInterval {
            shift = .locked
        } else {
            shift = shift == .off ? .on : .off
        }
        self.lastShiftTap = now
        rebuildKeyRows()
    }

    private func consumeOneShotShift() {
        guard shift == .on else { return }
        shift = .off
        rebuildKeyRows()
    }

    /// librime commits on its own for punctuation, a full buffer, or a schema
    /// rule. That text has already left the composition, so it has to reach the
    /// document now instead of waiting for the next space. A key librime did not
    /// consume is the host's responsibility, not something to drop.
    private func apply(_ outcome: RimeKeyOutcome, fallback: String?) {
        if let commit = outcome.commit {
            insertIntoDocument(commit)
        }
        if !outcome.handled, let fallback {
            insertIntoDocument(fallback)
        }
        refreshComposition()
    }

    private func handleSpace() {
        if language == .chinese, engine.snapshot.isComposing {
            // A space separates pinyin syllables in sentence mode. Keep the
            // Rime session alive and do not commit the current syllable: the
            // next letters extend the same full-sentence composition, which
            // lets librime and the Core ML reranker see the whole context.
            // Candidate selection, Return, or switching language commits it.
            refreshComposition()
            return
        }
        insertIntoDocument(" ")
    }

    private func handleBackspace() {
        if language == .chinese, engine.snapshot.isComposing {
            let outcome = engine.backspace()
            apply(outcome, fallback: nil)
            if outcome.handled {
                return
            }
        }
        deleteBackwardInDocument()
    }

    private func handleReturn() {
        if language == .chinese {
            commitPendingComposition()
        }
        insertIntoDocument("\n")
    }

    private func toggleLanguage() {
        commitPendingComposition()
        language.toggle()
        refreshSpaceAppearance()
        refreshComposition()
    }

    @objc private func toggleLanguageFromChrome(_ sender: Any? = nil) {
        if let gesture = sender as? UILongPressGestureRecognizer,
           gesture.state != .began {
            return
        }
        toggleLanguage()
    }

    private func turnCandidatePage(forward: Bool) {
        guard engine.snapshot.isComposing else { return }
        if forward, engine.snapshot.isLastPage {
            // The mockup has one chevron, not a pair of arrows. Wrapping keeps
            // that single control useful once the user has walked past the end.
            while engine.snapshot.pageNumber > 0 {
                apply(engine.turnPage(forward: false), fallback: nil)
            }
            return
        }
        apply(engine.turnPage(forward: forward), fallback: nil)
    }

    private func toggleCandidateExpansion() {
        setCandidatesExpanded(!isCandidatesExpanded)
    }

    private func setCandidatesExpanded(_ expanded: Bool) {
        guard expanded else {
            isCandidatesExpanded = false
            expandedItems = []
            expandedCandidates = []
            expandedPanel.isHidden = true
            keyboardRoot.isHidden = false
            updateExpandChevron()
            return
        }
        guard engine.snapshot.isComposing else { return }
        let items = makeBarCandidates(snapshot: engine.snapshot, preferRanked: false, acrossPages: true)
        guard !items.isEmpty else { return }
        expandedItems = items
        expandedCandidates = items.map(\.asRimeCandidate)
        isCandidatesExpanded = true
        expandedPanel.reload(candidates: expandedCandidates, highlightedIndex: 0)
        expandedPanel.isHidden = false
        keyboardRoot.isHidden = true
        updateExpandChevron()
        MobileLog.info(.rime, "candidates.expanded", [
            "count": String(items.count),
            "literal": String(items.contains { $0.isLiteral }),
        ])
    }

    private func updateExpandChevron() {
        var config = expandCandidatesButton.configuration ?? .plain()
        config.image = UIImage(systemName: isCandidatesExpanded ? "chevron.up" : "chevron.down")
        config.baseForegroundColor = isCandidatesExpanded ? Self.accent : .secondaryLabel
        expandCandidatesButton.configuration = config
        expandCandidatesButton.accessibilityLabel = MobileL10n.t(
            isCandidatesExpanded ? .candidateCollapse : .candidateExpand
        )
    }

    private func selectExpandedCandidate(at absoluteIndex: Int) {
        guard expandedItems.indices.contains(absoluteIndex) else { return }
        let item = expandedItems[absoluteIndex]
        if item.isLiteral {
            commitLiteralPreedit()
            return
        }
        guard let engineIndex = item.engineIndex else { return }
        let outcome = engine.selectAbsoluteCandidate(at: engineIndex)
        guard outcome.handled else {
            // Absolute select can fail on some pages; fall back to committing
            // the displayed text so the tap never dies silently.
            MobileLog.debug(.rime, "candidate.selectFailed", [
                "absolute": String(engineIndex),
                "via": "expanded",
            ])
            insertIntoDocument(item.text)
            engine.reset()
            setCandidatesExpanded(false)
            refreshComposition()
            return
        }
        MobileLog.info(.rime, "candidate.selected", [
            "absolute": String(engineIndex),
            "via": "expanded",
            "commitLen": String(outcome.commit?.count ?? 0),
        ])
        if privacyState.allowsPersistentLearning,
           let context = currentPredictionContext {
            (candidateRanker as? CoreMLCandidateRanker)?
                .record(item.asRimeCandidate, context: context)
        }
        setCandidatesExpanded(false)
        apply(outcome, fallback: item.text)
    }

    /// Commits whatever Latin the user typed, without asking librime to invent
    /// a Chinese reading for it. Random English input would otherwise sit in the
    /// composition with an empty or nonsense candidate bar.
    private func commitLiteralPreedit() {
        let text = engine.snapshot.preedit
        guard !text.isEmpty else { return }
        MobileLog.info(.rime, "candidate.selected", [
            "via": "literal",
            "textLen": String(text.count),
        ])
        engine.reset()
        setCandidatesExpanded(false)
        insertIntoDocument(text)
        rankedCandidates = []
        rankedCandidateIndices = []
        rankedPreedit = ""
        refreshComposition()
    }

    @discardableResult
    private func commitPendingComposition() -> Bool {
        guard let committed = engine.commitBestCandidate() else { return false }
        insertIntoDocument(committed)
        refreshComposition()
        return true
    }

    // MARK: - Document edits

    private func insertIntoDocument(_ text: String) {
        let shouldVerify = DiagnosticSettings.verifiesInsertion
        let before = shouldVerify ? textDocumentProxy.documentContextBeforeInput : nil
        isPerformingOwnEdit = true
        textDocumentProxy.insertText(text)
        clearOwnEditFlagAfterCallbacks()
        guard shouldVerify else { return }
        verifyInsertion(of: text, before: before)
    }

    /// Confirms a run-loop turn later that the host actually took the text.
    ///
    /// A host running its own text engine can drop or rewrite an insertion and
    /// report nothing back. Without this the keyboard's own log would claim it
    /// typed something the user never saw, which is the failure that makes a
    /// channel-specific bug impossible to argue about.
    private func verifyInsertion(of text: String, before: String?) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let after = textDocumentProxy.documentContextBeforeInput
            let outcome = InsertionProbe.evaluate(expected: text, before: before, after: after)
            MobileLog.emit(
                .insertion,
                "insert.verified",
                level: outcome == .landed ? .debug : .error,
                [
                    "outcome": outcome.rawValue,
                    "channel": hostChannel?.id ?? "unknown",
                    "text": MobileLog.fingerprint(text),
                    "beforeLen": before.map { String($0.count) } ?? "nil",
                    "afterLen": after.map { String($0.count) } ?? "nil",
                ]
            )
        }
    }

    private func deleteBackwardInDocument() {
        isPerformingOwnEdit = true
        textDocumentProxy.deleteBackward()
        clearOwnEditFlagAfterCallbacks()
    }

    private func clearOwnEditFlagAfterCallbacks() {
        // The host may deliver the change callbacks synchronously or on the next
        // main-queue turn, so hold the flag until that turn has passed.
        DispatchQueue.main.async { [weak self] in
            self?.isPerformingOwnEdit = false
        }
    }

    // MARK: - Composition display

    /// Shown instead of the composition when there is nothing being typed, so a
    /// degraded Rime session stays visible rather than looking like a keyboard
    /// that has forgotten the language. Otherwise blank — the spacebar already
    /// shows 拼 / ABC for the current mode.
    private var idlePreeditText: String {
        if rimeDegradedReason != nil, language == .chinese {
            return MobileL10n.t(.pinyinDegradedBadge)
        }
        return ""
    }

    private func refreshComposition() {
        let snapshot = engine.snapshot
        if rankedPreedit != snapshot.preedit {
            rankedCandidates = []
            rankedCandidateIndices = []
        }
        preeditLabel.text = snapshot.isComposing ? snapshot.preedit : idlePreeditText
        candidateStack.arrangedSubviews.forEach {
            candidateStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let usingRanked = !(rankedCandidates.isEmpty && !snapshot.candidates.isEmpty)
        let candidates = usingRanked ? rankedCandidates : snapshot.candidates
        let selected = selectedDisplayIndex(in: snapshot, usingRanked: usingRanked)
        for (index, candidate) in candidates.enumerated() {
            candidateStack.addArrangedSubview(
                makeCandidateButton(candidate, at: index, selected: index == selected)
            )
        }
        // "The engine offered candidates but the bar looked empty" and "the
        // engine offered none" are different bugs that look identical from the
        // outside. Only the counts separate them, so both are recorded. The
        // composition itself is what the user typed, so only its length is.
        MobileLog.debug(.rime, "candidates.drawn", [
            "preeditLen": String(snapshot.preedit.count),
            "engine": String(snapshot.candidates.count),
            "drawn": String(candidates.count),
        ])
        // Composition on its own line; candidates on the next. Do not merge them.
        let composing = snapshot.isComposing
        let idleText = idlePreeditText
        preeditLabel.isHidden = composing ? false : idleText.isEmpty
        expandCandidatesButton.isHidden = !composing
        expandCandidatesButton.isEnabled = composing
        clearButton.isHidden = !composing
        voiceButton.isHidden = composing
        statusLabel.isHidden = composing || (statusLabel.text?.isEmpty ?? true)
        if !composing, isCandidatesExpanded {
            setCandidatesExpanded(false)
        } else if isCandidatesExpanded {
            let items = makeBarCandidates(
                snapshot: snapshot,
                preferRanked: false,
                acrossPages: true
            )
            expandedItems = items
            expandedCandidates = items.map(\.asRimeCandidate)
            expandedPanel.reload(candidates: expandedCandidates, highlightedIndex: 0)
        }
        updateExpandChevron()
        scheduleCandidateRanking(for: snapshot)
    }

    private func clearComposition() {
        engine.reset()
        rankedCandidates = []
        rankedCandidateIndices = []
        rankedPreedit = ""
        setCandidatesExpanded(false)
        MobileLog.info(.rime, "composition.cleared", [:])
        refreshComposition()
    }

    private func scheduleCandidateRanking(for snapshot: RimeSnapshot) {
        guard snapshot.isComposing, !snapshot.candidates.isEmpty else {
            rankedCandidates = []
            rankedCandidateIndices = []
            return
        }
        let requestID = UUID()
        rankRequestID = requestID
        let context = PredictionContext(
            preedit: snapshot.preedit,
            documentContext: documentContextForInference,
            candidates: snapshot.candidates,
            language: language
        )
        Task { [weak self] in
            guard let ranked = await self?.candidateRanker.rank(context) else { return }
            await MainActor.run {
                guard let self, self.rankRequestID == requestID,
                      self.engine.snapshot.preedit == snapshot.preedit else { return }
                self.rankedCandidates = ranked
                // Match by text rather than Equatable identity: a ranker is free
                // to rebuild candidates, and a failed firstIndex left the display
                // row with no engine mapping — every tap then no-op'd silently.
                self.rankedCandidateIndices = ranked.compactMap { candidate in
                    snapshot.candidates.firstIndex { $0.text == candidate.text }
                }
                self.rankedPreedit = snapshot.preedit
                self.refreshCompositionWithoutRanking()
            }
        }
    }

    private func refreshCompositionWithoutRanking() {
        let snapshot = engine.snapshot
        candidateStack.arrangedSubviews.forEach {
            candidateStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        let selected = selectedDisplayIndex(in: snapshot, usingRanked: true)
        for (index, candidate) in rankedCandidates.enumerated() {
            candidateStack.addArrangedSubview(
                makeCandidateButton(candidate, at: index, selected: index == selected)
            )
        }
    }

    /// Where in the row librime's selection has ended up. The ranker reorders the
    /// candidates, so the engine's index is a position in a list the user is not
    /// looking at and has to be mapped back through the display order.
    private func selectedDisplayIndex(in snapshot: RimeSnapshot, usingRanked: Bool) -> Int? {
        guard snapshot.isComposing else { return nil }
        guard usingRanked else {
            return snapshot.candidates.indices.contains(snapshot.highlightedIndex)
                ? snapshot.highlightedIndex : nil
        }
        return rankedCandidateIndices.firstIndex(of: snapshot.highlightedIndex)
    }

    /// One line, with the selected candidate on a tinted pill.
    ///
    /// The title is built through `UIButton.Configuration` rather than set on the
    /// title label: configuration also carries the padding and the pill, so the
    /// button reports a height that accounts for them and the row can be sized
    /// by its contents.
    private func makeCandidateButton(
        _ candidate: RimeCandidate,
        at index: Int,
        selected: Bool
    ) -> UIButton {
        let button = UIButton(type: .system)
        // The index is part of the title because the digit keys select by it,
        // but it is the candidate that is being read, so it recedes.
        var title = AttributedString("\(index + 1) ")
        title.font = .preferredFont(forTextStyle: .footnote)
        title.foregroundColor = .secondaryLabel
        var word = AttributedString(candidate.text)
        word.font = .preferredFont(forTextStyle: .headline)
        word.foregroundColor = selected ? Self.accent : .label
        title.append(word)

        var configuration = UIButton.Configuration.plain()
        configuration.attributedTitle = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 9, bottom: 4, trailing: 9)
        if selected {
            configuration.background.backgroundColor = Self.accent.withAlphaComponent(0.13)
            configuration.background.cornerRadius = 9
        }
        button.configuration = configuration
        button.accessibilityLabel = MobileL10n.t(.candidateAccessibility, index + 1, candidate.text)
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            // Before the ranker answers, the row shows the engine order and the
            // index map is empty. Falling through to `index` is what makes a tap
            // land; requiring the map swallowed every press in that window.
            let engineIndex = rankedCandidateIndices.indices.contains(index)
                ? rankedCandidateIndices[index]
                : index
            let outcome = engine.selectCandidate(at: engineIndex)
            guard outcome.handled else {
                MobileLog.debug(.rime, "candidate.selectFailed", [
                    "display": String(index),
                    "engine": String(engineIndex),
                    "map": String(rankedCandidateIndices.count),
                ])
                return
            }
            MobileLog.info(.rime, "candidate.selected", [
                "display": String(index),
                "engine": String(engineIndex),
                "commitLen": String(outcome.commit?.count ?? 0),
            ])
            if privacyState.allowsPersistentLearning, let context = currentPredictionContext {
                (candidateRanker as? CoreMLCandidateRanker)?.record(candidate, context: context)
            }
            apply(outcome, fallback: nil)
        }, for: .touchUpInside)
        return button
    }

    private var currentPredictionContext: PredictionContext? {
        let snapshot = engine.snapshot
        guard snapshot.isComposing else { return nil }
        return PredictionContext(preedit: snapshot.preedit,
                                 documentContext: documentContextForInference,
                                 candidates: snapshot.candidates, language: language)
    }

    /// UITextDocumentProxy exposes only the text around the insertion point;
    /// this is the supported way for a custom keyboard to use dialogue context.
    /// The window is bounded again by PredictionContext before inference.
    private var documentContextForInference: String {
        guard privacyState.allowsDocumentContext else { return "" }
        let before = textDocumentProxy.documentContextBeforeInput ?? ""
        let after = textDocumentProxy.documentContextAfterInput ?? ""
        let selected = textDocumentProxy.selectedText ?? ""
        return "\(before)\u{001e}\(selected)\u{001f}\(after)"
    }

    // MARK: - Voice bridge

    private func startBridgeObservation() {
        if bridgeWatcher == nil {
            bridgeWatcher = VoiceBridgeWatcher { [weak self] in
                self?.refreshBridge()
            }
        }
        guard bridgeTimer == nil else { return }
        bridgeTimer = Timer.scheduledTimer(
            withTimeInterval: Self.bridgeBackstopInterval,
            repeats: true
        ) { [weak self] _ in
            self?.refreshBridge()
        }
    }

    private func stopBridgeObservation() {
        bridgeWatcher = nil
        bridgeTimer?.invalidate()
        bridgeTimer = nil
    }

    /// Automatic insertion is limited to the field that asked for dictation.
    /// The bridge is global to the App Group, so without that check a transcript
    /// requested in one app would be typed into whichever text field the
    /// keyboard happened to attach to next.
    private func refreshBridge() {
        let state = bridge.load()
        switch state.delivery(
            // The host connection can be temporarily invalid while iOS is
            // restarting PlugInKit. Do not dereference textDocumentProxy from
            // this bridge refresh path. A nil ID deliberately requires an
            // explicit tap before inserting a voice result.
            toDocument: currentDocumentID,
            alreadyInserted: lastInsertedRequestID
        ) {
        case .insert(let ready):
            deliver(ready)
        case .awaitExplicitInsert(let ready):
            // The timer re-evaluates this every two seconds; only the moment it
            // first becomes true is worth a line.
            if pendingResult?.requestID != ready.requestID {
                MobileLog.info(.bridge, "delivery.deferred", [
                    "request": ready.requestID.uuidString.prefix(8).lowercased(),
                    "target": ready.targetDocumentID?.uuidString.prefix(8).lowercased() ?? "none",
                    "document": currentDocumentID?.uuidString.prefix(8).lowercased() ?? "none",
                    "channel": hostChannel?.id ?? "unknown",
                    "reason": currentDocumentID == nil
                        ? "keyboard has no document identity"
                        : "transcript belongs to another field",
                ])
            }
            pendingResult = ready
            statusLabel.text = MobileL10n.t(.resultReadyElsewhere)
            statusLabel.isHidden = false
            updateVoiceButton()
        case .nothing:
            pendingResult = nil
            statusLabel.text = idleStatusText(for: state)
            statusLabel.isHidden = statusLabel.text?.isEmpty ?? true
            updateVoiceButton()
        }
    }

    /// Transient voice / degraded-engine notes only. Privacy ("Basic mode…")
    /// never belongs on the composition bar — Diagnostics already surfaces it.
    private func idleStatusText(for state: VoiceBridgeState) -> String {
        if !state.message.isEmpty {
            return state.message
        }
        if let rimeDegradedReason {
            return MobileL10n.t(.pinyinDegradedStatus, rimeDegradedReason)
        }
        return ""
    }

    private func deliver(_ state: VoiceBridgeState) {
        MobileLog.info(.bridge, "delivery.inserted", [
            "request": state.requestID.uuidString.prefix(8).lowercased(),
            "channel": hostChannel?.id ?? "unknown",
            "text": MobileLog.fingerprint(state.text),
            "ageMs": String(Int(Date().timeIntervalSince(state.updatedAt) * 1000)),
        ])
        insertIntoDocument(state.text)
        lastInsertedRequestID = state.requestID
        pendingResult = nil
        bridge.markConsumed(requestID: state.requestID)
        statusLabel.text = MobileL10n.t(.resultInserted)
        statusLabel.isHidden = false
        updateVoiceButton()
    }

    private func requestVoice() {
        // The identity recorded with the request is what decides, later,
        // whether the transcript may be inserted without a second tap.
        refreshHostContext()
        commitPendingComposition()
        // Tapping the key is the explicit consent that lets a result reach a
        // field other than the one that requested it.
        if let pendingResult, pendingResult.hasFreshResult() {
            deliver(pendingResult)
            return
        }
        let state = bridge.request(
            mode: voiceMode,
            documentID: currentDocumentID
        )
        statusLabel.text = state.message
        statusLabel.isHidden = state.message.isEmpty
        updateVoiceButton()
    }

    private func updateVoiceButton() {
        styleVoiceButton()
        if pendingResult == nil {
            voiceButton.accessibilityLabel = MobileL10n.t(.voiceKeyAccessibility, voiceMode.label)
        } else {
            // A finished transcript is waiting: keep the mic but say so.
            voiceButton.accessibilityLabel = MobileL10n.t(.voiceKeyInsertAccessibility)
            voiceButton.configuration?.baseForegroundColor = .systemOrange
        }
    }

    private func configureVoiceMenu() {
        voiceButton.menu = UIMenu(
            title: MobileL10n.t(.voiceModeMenuTitle),
            children: VoiceOutputMode.allCases.map { mode in
                UIAction(
                    title: mode.label,
                    state: mode == voiceMode ? .on : .off
                ) { [weak self] _ in
                    self?.selectVoiceMode(mode)
                }
            }
        )
        voiceButton.showsMenuAsPrimaryAction = false
    }

    private func selectVoiceMode(_ mode: VoiceOutputMode) {
        voiceMode = mode
        bridge.setMode(mode)
        updateVoiceButton()
        configureVoiceMenu()
        statusLabel.text = MobileL10n.t(.voiceModeSelected, mode.label)
        statusLabel.isHidden = false
    }
}

// MARK: - Candidate bar model

/// One entry in the candidate bar or expanded sheet.
private struct BarCandidate {
    let text: String
    /// Index into librime's candidate list. `nil` means "commit the raw preedit".
    let engineIndex: Int?

    var isLiteral: Bool { engineIndex == nil }
    var asRimeCandidate: RimeCandidate { RimeCandidate(text: text, comment: nil) }
}

private extension KeyboardViewController {
    /// Builds what the bar / sheet should show. Always keeps a literal Latin
    /// escape hatch when composing, so random English input is never a blank bar.
    func makeBarCandidates(
        snapshot: RimeSnapshot,
        preferRanked: Bool,
        acrossPages: Bool
    ) -> [BarCandidate] {
        let engineList: [RimeCandidate]
        let indexMap: [Int]
        if acrossPages {
            engineList = engine.allCandidates()
            indexMap = Array(engineList.indices)
        } else if preferRanked, !rankedCandidates.isEmpty {
            engineList = rankedCandidates
            indexMap = rankedCandidateIndices
        } else {
            engineList = snapshot.candidates
            indexMap = Array(snapshot.candidates.indices)
        }

        var items: [BarCandidate] = []
        for (display, candidate) in engineList.enumerated() {
            let engineIndex = indexMap.indices.contains(display) ? indexMap[display] : display
            items.append(BarCandidate(text: candidate.text, engineIndex: engineIndex))
        }

        let preedit = snapshot.preedit
        guard snapshot.isComposing, !preedit.isEmpty else { return items }
        guard !items.contains(where: { $0.text == preedit }) else { return items }

        let literal = BarCandidate(text: preedit, engineIndex: nil)
        // Long / spaced Latin reads as free English — put it first so the bar
        // is never a couple of obscure Chinese guesses and a sea of empty space.
        if preedit.contains(where: { $0 == " " || $0 == "'" }) || preedit.count >= 10 {
            items.insert(literal, at: 0)
        } else {
            items.append(literal)
        }
        return items
    }
}
