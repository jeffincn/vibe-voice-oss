import SwiftUI

struct TokenUsageReportView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let store = appState.tokenUsage
        let total = store.total
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Token 用量统计").font(.headline)
                Text("仅统计接口实际返回的 usage；本地模型或未返回 usage 的接口不会估算。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()

            if store.records.isEmpty {
                ContentUnavailableView(
                    "暂无用量数据",
                    systemImage: "number.circle",
                    description: Text("完成一次返回 usage 的转写、整理、翻译或 Prompt 优化后会显示在这里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("累计") {
                        usageRows(total)
                    }
                    Section("最近请求") {
                        ForEach(store.records.suffix(100).reversed()) { record in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(record.stage.label)
                                    Spacer()
                                    Text("\(record.usage.totalTokens) tokens")
                                        .monospacedDigit()
                                }
                                Text("\(record.model) · \(record.createdAt.formatted(date: .abbreviated, time: .standard))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                Text("共 \(store.records.count) 次 API 用量记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空记录", role: .destructive) { store.clear() }
                    .disabled(store.records.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    @ViewBuilder
    private func usageRows(_ usage: TokenUsage) -> some View {
        row("Input Token", usage.inputTokens)
        row("Cached Input Token（Input 明细）", usage.cachedInputTokens)
        row("Output Token", usage.outputTokens)
        row("Reasoning Token（Output 明细）", usage.reasoningTokens)
        row("Audio Input Token", usage.audioInputTokens)
        row("Audio Output Token", usage.audioOutputTokens)
        if let seconds = usage.audioSeconds {
            HStack {
                Text("Audio 时长")
                Spacer()
                Text(String(format: "%.1f 秒", seconds)).monospacedDigit()
            }
        }
        row("Total Token", usage.totalTokens)
    }

    private func row(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.formatted()).monospacedDigit()
        }
    }
}
