import UIKit

final class KeyboardViewController: UIInputViewController {
    /// The Darwin signal from the containing app is best-effort and coalescing,
    /// so a slow timer backs it up. It replaces the 0.4s poll this controller
    /// used to run for as long as the keyboard was on screen.
    private static let bridgeBackstopInterval: TimeInterval = 2

    private lazy var engine: RimeEngine = RimeEngineFactory.makeForKeyboard()
    private let bridge = VoiceBridgeStore()
    private var language: KeyboardLanguage = .chinese
    private var voiceMode: VoiceOutputMode = .polished
    private var lastInsertedRequestID: UUID?
    private var bridgeTimer: Timer?
    private var bridgeWatcher: VoiceBridgeWatcher?
    /// A finished transcript that belongs to a different text field. It waits
    /// here until the user goes back to that field or asks for it explicitly.
    private var pendingResult: VoiceBridgeState?

    private let preeditLabel = UILabel()
    private let candidateStack = UIStackView()
    private let statusLabel = UILabel()
    private let languageButton = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        voiceMode = bridge.load().mode
        view.backgroundColor = UIColor.systemGray6
        configureLayout()
        refreshComposition()
        refreshBridge()
        startBridgeObservation()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
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

        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            view.heightAnchor.constraint(greaterThanOrEqualToConstant: 286),
        ])
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
        backspace.widthAnchor.constraint(equalToConstant: 48).isActive = true
        backspace.addAction(UIAction { [weak self] _ in self?.handleBackspace() }, for: .touchUpInside)

        let enter = keyButton("↵")
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
            engine.process(letter: letter)
            refreshComposition()
        case .english:
            insertIntoDocument(String(letter).lowercased())
        }
    }

    private func handleSpace() {
        if language == .chinese, commitPendingComposition() {
            return
        }
        insertIntoDocument(" ")
    }

    private func handleBackspace() {
        if language == .chinese, !engine.snapshot.preedit.isEmpty {
            engine.backspace()
            refreshComposition()
        } else {
            textDocumentProxy.deleteBackward()
        }
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

    private func refreshComposition() {
        let snapshot = engine.snapshot
        preeditLabel.text = snapshot.preedit.isEmpty ? language.toggleLabel : snapshot.preedit
        candidateStack.arrangedSubviews.forEach {
            candidateStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, candidate) in snapshot.candidates.prefix(8).enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(candidate.text, for: .normal)
            button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
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
        guard state.hasFreshResult() else {
            pendingResult = nil
            statusLabel.text = state.message.isEmpty ? state.status.rawValue : state.message
            updateVoiceButton()
            return
        }

        if state.requestID != lastInsertedRequestID,
           state.targets(documentID: textDocumentProxy.documentIdentifier) {
            deliver(state)
            return
        }

        pendingResult = state
        statusLabel.text = "结果已就绪，回到原输入框或点麦克风插入"
        updateVoiceButton()
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
        textDocumentProxy.insertText(text)
    }

    private func updateVoiceButton() {
        let title = pendingResult == nil ? "🎙 \(voiceMode.label)" : "🎙 插入"
        voiceButton.setTitle(title, for: .normal)
    }

    @objc
    private func handleGlobe(_ sender: UIButton, event: UIEvent) {
        handleInputModeList(from: sender, with: event)
    }
}
