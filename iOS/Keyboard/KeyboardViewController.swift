import UIKit

final class KeyboardViewController: UIInputViewController {
    private let engine: RimeEngine = PrototypeRimeEngine()
    private let bridge = VoiceBridgeStore()
    private var language: KeyboardLanguage = .chinese
    private var voiceMode: VoiceOutputMode = .polished
    private var lastInsertedRequestID: UUID?
    private var bridgeTimer: Timer?

    private let preeditLabel = UILabel()
    private let candidateStack = UIStackView()
    private let statusLabel = UILabel()
    private let languageButton = UIButton(type: .system)
    private let voiceButton = UIButton(type: .system)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.systemGray6
        configureLayout()
        refreshComposition()
        refreshBridge()
        bridgeTimer = Timer.scheduledTimer(
            withTimeInterval: 0.4,
            repeats: true
        ) { [weak self] _ in
            self?.refreshBridge()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        bridgeTimer?.invalidate()
        bridgeTimer = nil
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

        voiceButton.setTitle("🎙 \(voiceMode.label)", for: .normal)
        style(button: voiceButton)
        voiceButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72).isActive = true
        voiceButton.addAction(UIAction { [weak self] _ in self?.requestVoice() }, for: .touchUpInside)

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
            textDocumentProxy.insertText(String(letter).lowercased())
        }
    }

    private func handleSpace() {
        if language == .chinese, let committed = engine.commitBestCandidate() {
            textDocumentProxy.insertText(committed)
            refreshComposition()
        } else {
            textDocumentProxy.insertText(" ")
        }
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
        if language == .chinese, let committed = engine.commitBestCandidate() {
            textDocumentProxy.insertText(committed)
            refreshComposition()
        }
        textDocumentProxy.insertText("\n")
    }

    private func toggleLanguage() {
        if let committed = engine.commitBestCandidate() {
            textDocumentProxy.insertText(committed)
        }
        language.toggle()
        languageButton.setTitle(language.toggleLabel, for: .normal)
        refreshComposition()
    }

    private func requestVoice() {
        if let committed = engine.commitBestCandidate() {
            textDocumentProxy.insertText(committed)
            refreshComposition()
        }
        let state = bridge.request(mode: voiceMode)
        statusLabel.text = state.message
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
                guard let text = self?.engine.selectCandidate(at: index) else { return }
                self?.textDocumentProxy.insertText(text)
                self?.refreshComposition()
            }, for: .touchUpInside)
            candidateStack.addArrangedSubview(button)
        }
    }

    private func refreshBridge() {
        let state = bridge.load()
        statusLabel.text = state.message.isEmpty ? state.status.rawValue : state.message
        guard state.status == .ready,
              !state.text.isEmpty,
              state.requestID != lastInsertedRequestID else { return }
        textDocumentProxy.insertText(state.text)
        lastInsertedRequestID = state.requestID
        bridge.markConsumed(requestID: state.requestID)
    }

    @objc
    private func handleGlobe(_ sender: UIButton, event: UIEvent) {
        handleInputModeList(from: sender, with: event)
    }
}
