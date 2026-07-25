import SwiftUI

struct MobileHomeView: View {
    @State private var bridgeState = VoiceBridgeStore().load()
    @State private var testResult = "你好，这是 Vibe Voice 的键盘桥接测试。"
    private let bridge = VoiceBridgeStore()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    setupCard
                    bridgeCard
                    modelCard
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Vibe Voice")
            .task {
                while !Task.isCancelled {
                    bridgeState = bridge.load()
                    try? await Task.sleep(for: .milliseconds(500))
                }
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("iOS 0.7.0 Alpha", systemImage: "waveform.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.tint)
            Text("完整中英键盘、Rime 全拼与语音输入的移动端工作区。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("启用键盘", systemImage: "keyboard")
                .font(.headline)
            Text("设置 → 通用 → 键盘 → 键盘 → 添加新键盘 → Vibe Voice。语音桥接需要“允许完全访问”；基础中英文输入将保持离线可用。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var bridgeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("语音桥接", systemImage: "mic.fill")
                    .font(.headline)
                Spacer()
                Text(bridgeState.status.rawValue)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            TextField("测试输出", text: $testResult, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("发布到键盘") {
                    bridge.publish(status: .ready, text: testResult, message: "可插入")
                    bridgeState = bridge.load()
                }
                .buttonStyle(.borderedProminent)
                Button("重置") {
                    bridge.reset()
                    bridgeState = bridge.load()
                }
                .buttonStyle(.bordered)
            }
            Text("这是阶段一的确定性桥接验证入口，后续由真实录音和 ASR 管线替换。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("本地模型", systemImage: "cpu")
                .font(.headline)
            LabeledContent("WhisperKit", value: "待接入")
            LabeledContent("Qwen3-ASR", value: "实验性")
            LabeledContent("Rime", value: "接口已建立")
        }
        .cardStyle()
    }
}

private extension View {
    func cardStyle() -> some View {
        padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
