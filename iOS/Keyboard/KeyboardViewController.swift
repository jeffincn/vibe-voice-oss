import UIKit

final class KeyboardViewController: UIInputViewController {
    /// The Darwin signal from the containing app is best-effort and coalescing,
    /// so a slow timer backs it up. It replaces the 0.4s poll this controller
    /// used to run for as long as the keyboard was on screen.
    private static let bridgeBackstopInterval: TimeInterval = 2
    /// Height of the keys themselves. The home indicator inset is added on top
    /// in viewSafeAreaInsetsDidChange.
    private static let contentHeight: CGFloat = 286
    /// Two taps closer together than this lock the shift key.
    private static let shiftLockInterval: TimeInterval = 0.35

    private var engine: RimeEngine = PrototypeRimeEngine()
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
    /// The host text field the composition currently belongs to.
    private var currentDocumentID: UUID?
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
    private let previousPageButton = UIButton(type: .system)
    private let nextPageButton = UIButton(type: .system)
    private let statusLabel = UILabel()
    private let keyRowsStack = UIStackView()
    private let planeButton = UIButton(type: .system)
    private let languageButton = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        voiceMode = bridge.load().mode
        let rime = RimeEngineFactory.makeForKeyboard()
        engine = rime.engine
        rimeDegradedReason = rime.degradedReason
        view.backgroundColor = UIColor.systemGray6
        configureLayout()
        rebuildKeyRows()
        refreshComposition()
        refreshBridge()
        startBridgeObservation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncWithHostDocument()
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
        syncWithHostDocument()
    }

    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        super.selectionWillChange(textInput)
        // The user moved the caret away from where the composition was being
        // built. Committing it now would drop the characters somewhere else.
        guard !isPerformingOwnEdit, engine.snapshot.isComposing else { return }
        engine.reset()
        refreshComposition()
    }

    /// A keyboard extension is reused across text fields and across apps within
    /// a host. Anything still in the composition belongs to the field it was
    /// typed in and must not follow the user to the next one.
    private func syncWithHostDocument() {
        let documentID = textDocumentProxy.documentIdentifier
        guard documentID != currentDocumentID else { return }
        currentDocumentID = documentID
        engine.reset()
        refreshComposition()
        refreshBridge()
    }

    // MARK: - Layout

    private func configureLayout() {
        preeditLabel.font = .preferredFont(forTextStyle: .callout)
        preeditLabel.textColor = .secondaryLabel
        preeditLabel.setContentHuggingPriority(.required, for: .horizontal)

        candidateStack.axis = .horizontal
        candidateStack.spacing = 6
        candidateStack.alignment = .fill

        let candidateScroll = UIScrollView()
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

        configurePageButton(previousPageButton, title: "◀", label: "上一页候选") { [weak self] in
            self?.turnCandidatePage(forward: false)
        }
        configurePageButton(nextPageButton, title: "▶", label: "下一页候选") { [weak self] in
            self?.turnCandidatePage(forward: true)
        }

        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .right
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let header = UIStackView(arrangedSubviews: [
            preeditLabel,
            previousPageButton,
            candidateScroll,
            nextPageButton,
            statusLabel,
        ])
        header.axis = .horizontal
        header.spacing = 8
        header.alignment = .center
        header.heightAnchor.constraint(equalToConstant: 38).isActive = true

        keyRowsStack.axis = .vertical
        keyRowsStack.spacing = 7
        keyRowsStack.distribution = .fillEqually

        let keyboard = UIStackView(arrangedSubviews: [header, keyRowsStack, makeUtilityRow()])
        keyboard.axis = .vertical
        keyboard.spacing = 7
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)

        // Keys pinned to the safe area keep the bottom row clear of the home
        // indicator and, in landscape, of the sensor housing.
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 6),
            keyboard.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -6),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            keyboard.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -6),
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
        planeButton.setTitle(plane.alternateLabel, for: .normal)
        planeButton.accessibilityLabel = plane == .letters ? "数字与符号" : "字母"
    }

    private func makeKeyRow(_ keys: [KeyboardKey], inset: Bool) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
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
        let button = keyButton(title(for: key))
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

    private func title(for key: KeyboardKey) -> String {
        switch key {
        case let .character(text):
            return shift.isRaised ? text.uppercased() : text
        case .shift:
            return shift == .locked ? "⇪" : "⇧"
        case let .plane(target):
            return target == .symbols ? "#+=" : "123"
        case .backspace:
            return "⌫"
        }
    }

    private func accessibilityLabel(for key: KeyboardKey) -> String {
        switch key {
        case let .character(text):
            // VoiceOver announces a bare glyph inconsistently across voices.
            return shift.isRaised ? text.uppercased() : text
        case .shift:
            return shift == .locked ? "大写锁定" : "上档"
        case let .plane(target):
            return target == .symbols ? "更多符号" : "数字与符号"
        case .backspace:
            return "删除"
        }
    }

    private func makeUtilityRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fill

        style(button: planeButton)
        planeButton.widthAnchor.constraint(equalToConstant: 46).isActive = true
        planeButton.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            handle(.plane(plane.alternate))
        }, for: .touchUpInside)

        let globe = keyButton("🌐")
        globe.accessibilityLabel = "切换键盘"
        globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
        globe.addTarget(self, action: #selector(handleGlobe(_:event:)), for: .allTouchEvents)

        languageButton.setTitle(language.toggleLabel, for: .normal)
        languageButton.accessibilityLabel = "中英切换"
        style(button: languageButton)
        languageButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        languageButton.addAction(UIAction { [weak self] _ in self?.toggleLanguage() }, for: .touchUpInside)

        let space = keyButton("空格")
        space.accessibilityLabel = "空格"
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        space.addAction(UIAction { [weak self] _ in self?.handleSpace() }, for: .touchUpInside)

        style(button: voiceButton)
        updateVoiceButton()
        voiceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        voiceButton.addAction(UIAction { [weak self] _ in self?.requestVoice() }, for: .touchUpInside)
        configureVoiceMenu()

        let enter = keyButton("↵")
        enter.accessibilityLabel = "换行"
        enter.widthAnchor.constraint(equalToConstant: 44).isActive = true
        enter.addAction(UIAction { [weak self] _ in self?.handleReturn() }, for: .touchUpInside)

        [planeButton, globe, languageButton, space, voiceButton, enter]
            .forEach(row.addArrangedSubview)
        return row
    }

    private func configurePageButton(
        _ button: UIButton,
        title: String,
        label: String,
        action: @escaping () -> Void
    ) {
        button.setTitle(title, for: .normal)
        button.accessibilityLabel = label
        button.titleLabel?.font = .preferredFont(forTextStyle: .footnote)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    private func keyButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        style(button: button)
        return button
    }

    private func style(button: UIButton) {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = .secondarySystemBackground
        configuration.baseForegroundColor = .label
        configuration.cornerStyle = .medium
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 4, bottom: 9, trailing: 4)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
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

        if language == .chinese, output.count == 1, let character = output.first, character.isASCII {
            if character.isNumber, selectCandidateByDigit(character) {
                return
            }
            // An uppercase letter is an acronym or a name, not a continuation of
            // a pinyin syllable. Feeding it to librime would instead trip
            // ascii_composer's mode switch.
            if !character.isUppercase {
                apply(engine.process(character: character), fallback: output)
                return
            }
        }

        commitPendingComposition()
        insertIntoDocument(output)
    }

    /// Digits pick from the visible candidate page while composing. librime can
    /// be configured to do this, but only through schema keys this project does
    /// not ship, so the keyboard owns the rule.
    private func selectCandidateByDigit(_ digit: Character) -> Bool {
        let snapshot = engine.snapshot
        guard snapshot.isComposing, let value = digit.wholeNumberValue else { return false }
        let index = value == 0 ? 9 : value - 1
        guard snapshot.candidates.indices.contains(index),
              let text = engine.selectCandidate(at: index) else { return false }
        insertIntoDocument(text)
        refreshComposition()
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
        if language == .chinese, commitPendingComposition() {
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
        languageButton.setTitle(language.toggleLabel, for: .normal)
        refreshComposition()
    }

    private func turnCandidatePage(forward: Bool) {
        guard engine.snapshot.isComposing else { return }
        apply(engine.turnPage(forward: forward), fallback: nil)
    }

    @discardableResult
    private func commitPendingComposition() -> Bool {
        guard let committed = engine.commitBestCandidate() else { return false }
        insertIntoDocument(committed)
        refreshComposition()
        return true
    }

    @objc private func handleGlobe(_ sender: UIButton, event: UIEvent) {
        handleInputModeList(from: sender, with: event)
    }

    // MARK: - Document edits

    private func insertIntoDocument(_ text: String) {
        isPerformingOwnEdit = true
        textDocumentProxy.insertText(text)
        clearOwnEditFlagAfterCallbacks()
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
    /// that has forgotten the language.
    private var idlePreeditText: String {
        if rimeDegradedReason != nil, language == .chinese {
            return "⚠️ 拼音降级"
        }
        return language.toggleLabel
    }

    private func refreshComposition() {
        let snapshot = engine.snapshot
        preeditLabel.text = snapshot.isComposing ? snapshot.preedit : idlePreeditText
        candidateStack.arrangedSubviews.forEach {
            candidateStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, candidate) in snapshot.candidates.enumerated() {
            candidateStack.addArrangedSubview(
                makeCandidateButton(candidate, at: index)
            )
        }
        // Paging is the only way past the first page: the candidate bar shows
        // one page at a time because that is what librime's menu returns.
        previousPageButton.isHidden = !snapshot.isComposing
        nextPageButton.isHidden = !snapshot.isComposing
        previousPageButton.isEnabled = snapshot.pageNumber > 0
        nextPageButton.isEnabled = !snapshot.isLastPage
    }

    private func makeCandidateButton(_ candidate: RimeCandidate, at index: Int) -> UIButton {
        let button = UIButton(type: .system)
        // The index is part of the title because the digit keys select by it.
        button.setTitle("\(index + 1) \(candidate.text)", for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        button.accessibilityLabel = "候选 \(index + 1)：\(candidate.text)"
        button.addAction(UIAction { [weak self] _ in
            guard let self, let text = engine.selectCandidate(at: index) else { return }
            insertIntoDocument(text)
            refreshComposition()
        }, for: .touchUpInside)
        return button
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
            toDocument: textDocumentProxy.documentIdentifier,
            alreadyInserted: lastInsertedRequestID
        ) {
        case .insert(let ready):
            deliver(ready)
        case .awaitExplicitInsert(let ready):
            pendingResult = ready
            statusLabel.text = "结果已就绪，回到原输入框或点麦克风插入"
            updateVoiceButton()
        case .nothing:
            pendingResult = nil
            statusLabel.text = idleStatusText(for: state)
            updateVoiceButton()
        }
    }

    /// A degraded Rime session outlives any single bridge update, so it keeps
    /// the status line whenever the bridge has nothing more urgent to say.
    private func idleStatusText(for state: VoiceBridgeState) -> String {
        if !state.message.isEmpty {
            return state.message
        }
        if let rimeDegradedReason {
            return "拼音降级：\(rimeDegradedReason)"
        }
        return state.status.rawValue
    }

    private func deliver(_ state: VoiceBridgeState) {
        insertIntoDocument(state.text)
        lastInsertedRequestID = state.requestID
        pendingResult = nil
        bridge.markConsumed(requestID: state.requestID)
        statusLabel.text = "已插入"
        updateVoiceButton()
    }

    private func requestVoice() {
        commitPendingComposition()
        // Tapping the key is the explicit consent that lets a result reach a
        // field other than the one that requested it.
        if let pendingResult, pendingResult.hasFreshResult() {
            deliver(pendingResult)
            return
        }
        let state = bridge.request(
            mode: voiceMode,
            documentID: textDocumentProxy.documentIdentifier
        )
        statusLabel.text = state.message
        updateVoiceButton()
    }

    private func updateVoiceButton() {
        if pendingResult == nil {
            voiceButton.setTitle("🎙 \(voiceMode.label)", for: .normal)
            voiceButton.accessibilityLabel = "语音输入，\(voiceMode.label)模式"
        } else {
            voiceButton.setTitle("🎙 插入", for: .normal)
            voiceButton.accessibilityLabel = "插入已完成的语音结果"
        }
    }

    private func configureVoiceMenu() {
        voiceButton.menu = UIMenu(
            title: "语音输出模式",
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
        statusLabel.text = "已选择\(mode.label)模式"
    }
}
