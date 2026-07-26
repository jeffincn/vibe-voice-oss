import SwiftUI

/// A self-contained chat surface for exercising the same text field a user
/// would use in Messages. It intentionally keeps the keyboard visible while
/// voice work is handed to the containing app, making the app/extension handoff
/// easy to observe during simulator and device testing.
struct InputPlaygroundView: View {
    @ObservedObject var voiceController: MobileVoiceController
    @FocusState private var inputFocused: Bool
    @State private var draft = ""
    @State private var messages: [PlaygroundMessage] = []

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

                TextField(MobileL10n.t(.playgroundPlaceholder), text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .focused($inputFocused)
                    .accessibilityIdentifier("playground.input")
                    .onSubmit(sendDraft)

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

private struct PlaygroundMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isOutgoing: Bool
}
