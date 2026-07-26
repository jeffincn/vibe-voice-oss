import UIKit

final class KeyboardViewController: UIInputViewController {
    /// The Darwin signal from the containing app is best-effort and coalescing,
    /// so a slow timer backs it up. It replaces the 0.4s poll this controller
    /// used to run for as long as the keyboard was on screen.
    private static let bridgeBackstopInterval: TimeInterval = 2
    /// Height of the keys themselves. The home indicator inset is added on top
    /// in viewSafeAreaInsetsDidChange.
    private static let contentHeight: CGFloat = 286

    private var engine: RimeEngine = PrototypeRimeEngine()
    /// Non-nil when librime failed to start and the prototype engine is standing
    /// in with its ten-word lexicon.
    private var rimeDegradedReason: String?
    private let bridge = VoiceBridgeStore()
    private var language: KeyboardLanguage = .chinese
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
    private let statusLabel = UILabel()
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

    override func textDidChange(_ textInput: (any UITextInput)?) {
        super.textDidChange(textInput)
        syncWithHostDocument()
    }

    override func selectionWillChange(_ textInput: (any UITextInput)?) {
        super.selectionWillChange(textInput)
        // The user moved the caret away from where the composition was being
        // built. Committing it now would drop the characters somewhere else.
        guard !isPerformingOwnEdit, !engine.snapshot.preedit.isEmpty else { return }
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

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        stopBridgeObservation()
    }

    deinit {
        bridgeTimer?.invalidate()
        bridgeWatcher = nil
    }

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

        statusLabel.font = .preferredFont(forTextStyle: .caption2)
        statusLabel.textColor = .secondaryLabel
        statusLabel.textAlignment = .right

        let header = UIStackView(arrangedSubviews: [preeditLabel, candidateScroll, statusLabel])
        header.axis = .horizontal
        header.spacing = 8
        header.alignment = .center
        header.heightAnchor.constraint(equalToConstant: 38).isActive = true

        let rows = [
            makeLetterRow("QWERTYUIOP"),
            makeLetterRow("ASDFGHJKL"),
            makeLetterRow("ZXCVBNM"),
            makeUtilityRow(),
        ]
        let keyboard = UIStackView(arrangedSubviews: [header] + rows)
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

    private func makeLetterRow(_ letters: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fillEqually
        for letter in letters {
            let button = keyButton(String(letter))
            button.accessibilityIdentifier = "key.\(letter.lowercased())"
            // Without a label VoiceOver reads the glyph, which for a single
            // letter is announced inconsistently across voices.
            button.accessibilityLabel = String(letter)
            button.addAction(UIAction { [weak self] _ in
                self?.handleLetter(letter)
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func makeUtilityRow() -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 5
        row.distribution = .fill

        let globe = keyButton("🌐")
        globe.accessibilityLabel = "切换键盘"
        globe.widthAnchor.constraint(equalToConstant: 44).isActive = true
        globe.addTarget(self, action: #selector(handleGlobe(_:event:)), for: .allTouchEvents)

        languageButton.setTitle(language.toggleLabel, for: .normal)
        style(button: languageButton)
        languageButton.widthAnchor.constraint(equalToConstant: 48).isActive = true
        languageButton.addAction(UIAction { [weak self] _ in self?.toggleLanguage() }, for: .touchUpInside)

        let space = keyButton("空格")
        space.addAction(UIAction { [weak self] _ in self?.handleSpace() }, for: .touchUpInside)

        style(button: voiceButton)
        updateVoiceButton()
        voiceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        voiceButton.addAction(UIAction { [weak self] _ in self?.requestVoice() }, for: .touchUpInside)
        configureVoiceMenu()

        let backspace = keyButton("⌫")
        backspace.accessibilityLabel = "删除"
        backspace.widthAnchor.constraint(equalToConstant: 48).isActive = true
        backspace.addAction(UIAction { [weak self] _ in self?.handleBackspace() }, for: .touchUpInside)

        let enter = keyButton("↵")
        enter.accessibilityLabel = "换行"
        enter.widthAnchor.constraint(equalToConstant: 44).isActive = true
        enter.addAction(UIAction { [weak self] _ in self?.handleReturn() }, for: .touchUpInside)

        [globe, languageButton, space, voiceButton, backspace, enter].forEach(row.addArrangedSubview)
        return row
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
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 8, bottom: 9, trailing: 8)
        button.configuration = configuration
        button.titleLabel?.font = .preferredFont(forTextStyle: .body)
    }

    private func handleLetter(_ letter: Character) {
        switch language {
        case .chinese:
            apply(engine.process(letter: letter), fallback: String(letter).lowercased())
        case .english:
            insertIntoDocument(String(letter).lowercased())
        }
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
        if language == .chinese, !engine.snapshot.preedit.isEmpty {
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

    @discardableResult
    private func commitPendingComposition() -> Bool {
        guard let committed = engine.commitBestCandidate() else { return false }
        insertIntoDocument(committed)
        refreshComposition()
        return true
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
        preeditLabel.text = snapshot.preedit.isEmpty ? idlePreeditText : snapshot.preedit
        candidateStack.arrangedSubviews.forEach {
            candidateStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, candidate) in snapshot.candidates.prefix(8).enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(candidate.text, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
            button.accessibilityLabel = "候选 \(index + 1)：\(candidate.text)"
            button.addAction(UIAction { [weak self] _ in
                guard let self, let text = engine.selectCandidate(at: index) else { return }
                insertIntoDocument(text)
                refreshComposition()
            }, for: .touchUpInside)
            candidateStack.addArrangedSubview(button)
        }
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

    private func updateVoiceButton() {
        if pendingResult == nil {
            voiceButton.setTitle("🎙 \(voiceMode.label)", for: .normal)
            voiceButton.accessibilityLabel = "语音输入，\(voiceMode.label)模式"
        } else {
            voiceButton.setTitle("🎙 插入", for: .normal)
            voiceButton.accessibilityLabel = "插入已完成的语音结果"
        }
    }

    @objc
    private func handleGlobe(_ sender: UIButton, event: UIEvent) {
        handleInputModeList(from: sender, with: event)
    }
}
