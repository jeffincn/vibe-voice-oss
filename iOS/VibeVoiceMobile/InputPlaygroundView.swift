import SwiftUI

/// A self-contained chat surface for exercising the same text field a user
/// would use in Messages. It intentionally keeps the keyboard visible while
/// voice work is handed to the containing app, making the app/extension handoff
/// easy to observe during simulator and device testing.
struct InputPlaygroundView: View {
    @ObservedObject var voiceController: MobileVoiceController
    @State private var inputFocused = false
    @State private var draft = ""
    @State private var messages: [PlaygroundMessage] = []
    @State private var isRefining = false
    @State private var refinementError: String?
    @State private var isReasoning = false
    @State private var reasoningError: String?

    var body: some View {
        VStack(spacing: 0) {
            conversation
            composer
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(MobileL10n.t(.playgroundConversationName))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker(
                        MobileL10n.t(.homeOutputTitle),
                        selection: Binding(
                            get: { voiceController.outputMode },
                            set: { voiceController.selectOutputMode($0) }
                        )
                    ) {
                        ForEach(VoiceOutputMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .accessibilityIdentifier("playground.outputMode")
            }
        }
        .onChange(of: voiceController.transcript) { _, transcript in
            guard !transcript.isEmpty, voiceController.phase == .ready else { return }
            draft = transcript
            inputFocused = true
        }
        .onAppear {
            inputFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .playgroundSendDraft)) { _ in
            sendDraft()
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 10) {
                    HStack {
                        Spacer(minLength: 0)
                        Text(MobileL10n.t(.playgroundHint))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)

                    if messages.isEmpty {
                        ContentUnavailableView(
                            MobileL10n.t(.playgroundTitle),
                            systemImage: "message.and.waveform",
                            description: Text(MobileL10n.t(.playgroundEmpty))
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 34)
                    } else {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
        .accessibilityIdentifier("playground.conversation")
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if voiceController.phase != .idle {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(voiceController.phase.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .accessibilityIdentifier("playground.voiceStatus")
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    if voiceController.phase == .recording {
                        voiceController.stopAndTranscribe()
                    } else {
                        voiceController.startRecording()
                    }
                } label: {
                    Image(systemName: voiceController.phase == .recording ? "stop.fill" : "mic.fill")
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(voiceController.phase == .processing || voiceController.phase == .preparingModel)
                .accessibilityLabel(
                    MobileL10n.t(
                        voiceController.phase == .recording
                            ? .playgroundVoiceStop
                            : .playgroundVoice
                    )
                )
                .accessibilityIdentifier("playground.voice")

                ChineseInputTextView(text: $draft, isFirstResponder: $inputFocused,
                                     placeholder: MobileL10n.t(.playgroundPlaceholder))
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityIdentifier("playground.input")

                Button(action: sendDraft) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(MobileL10n.t(.playgroundSend))
                .accessibilityIdentifier("playground.send")
            }
            HStack(spacing: 6) {
                Image(systemName: "character.cursor.ibeam")
                Text("中文拼音模式 · 可用地球键切换 Vibe Voice")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button {
                    isRefining = true
                    refinementError = nil
                    Task {
                        do {
                            draft = try await SystemTextComposer.refine(draft)
                        } catch {
                            refinementError = error.localizedDescription
                        }
                        isRefining = false
                    }
                } label: {
                    Label("整句增强", systemImage: "sparkles")
                }
                .buttonStyle(.bordered)
                .disabled(isRefining || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("playground.refine")
                if isRefining { ProgressView().controlSize(.small) }
                if let refinementError {
                    Text(refinementError).font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    isReasoning = true
                    reasoningError = nil
                    Task {
                        do {
                            let result = try await SystemTextComposer.inferHiddenContext(draft)
                            messages.append(PlaygroundMessage(text: result, isOutgoing: false))
                        } catch {
                            reasoningError = error.localizedDescription
                        }
                        isReasoning = false
                    }
                } label: {
                    Label("模拟推理", systemImage: "brain.head.profile")
                }
                .buttonStyle(.bordered)
                .disabled(isReasoning || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("playground.reasoning")
                if isReasoning { ProgressView().controlSize(.small) }
                if let reasoningError {
                    Text(reasoningError).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.thinMaterial)
    }

    private func messageBubble(_ message: PlaygroundMessage) -> some View {
        HStack {
            if message.isOutgoing { Spacer(minLength: 48) }
            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 3) {
                Text(message.isOutgoing
                    ? MobileL10n.t(.playgroundYou)
                    : MobileL10n.t(.playgroundAssistant))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(message.text)
                    .font(.body)
                    .foregroundStyle(message.isOutgoing ? .white : .primary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(message.isOutgoing ? Color.accentColor : Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if !message.isOutgoing { Spacer(minLength: 48) }
        }
    }

    private func sendDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        messages.append(PlaygroundMessage(text: text, isOutgoing: true))
        draft = ""
        inputFocused = true
    }
}

/// UIKit-backed editor that asks iOS for the last-used Simplified Chinese
/// input mode. This prevents the playground from silently opening in English
/// QWERTY; the globe key remains the user-controlled way to select Vibe Voice.
private struct ChineseInputTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool
    let placeholder: String

    func makeUIView(context: Context) -> ChineseTextView {
        let view = ChineseTextView()
        view.delegate = context.coordinator
        view.font = .preferredFont(forTextStyle: .body)
        view.textColor = .label
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.textContainer.lineBreakMode = .byWordWrapping
        view.textContainer.maximumNumberOfLines = 4
        view.textContainer.lineFragmentPadding = 0
        view.text = text
        view.accessibilityIdentifier = "playground.input"
        view.accessibilityLabel = placeholder
        return view
    }

    func updateUIView(_ uiView: ChineseTextView, context: Context) {
        if uiView.text != text { uiView.text = text }
        if isFirstResponder, !uiView.isFirstResponder { uiView.becomeFirstResponder() }
        if !isFirstResponder, uiView.isFirstResponder { uiView.resignFirstResponder() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ChineseInputTextView
        init(_ parent: ChineseInputTextView) { self.parent = parent }
        func textViewDidChange(_ textView: UITextView) { parent.text = textView.text }
        func textViewDidBeginEditing(_ textView: UITextView) { parent.isFirstResponder = true }
        func textViewDidEndEditing(_ textView: UITextView) { parent.isFirstResponder = false }
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange,
                      replacementText replacement: String) -> Bool {
            if replacement == "\n" { parent.send() ; return false }
            return true
        }
    }

    private func send() { NotificationCenter.default.post(name: .playgroundSendDraft, object: nil) }
}

private final class ChineseTextView: UITextView {
    override var textInputMode: UITextInputMode? {
        UITextInputMode.activeInputModes.first(where: { $0.primaryLanguage?.hasPrefix("zh-Hans") == true })
            ?? super.textInputMode
    }
}

private extension Notification.Name {
    static let playgroundSendDraft = Notification.Name("VibeVoice.playground.sendDraft")
}

private struct PlaygroundMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isOutgoing: Bool
}
