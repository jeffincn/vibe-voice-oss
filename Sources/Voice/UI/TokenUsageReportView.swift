import SwiftUI

struct TokenUsageReportView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let store = appState.tokenUsage
        let total = store.total
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.t(.tokenUsageHeader)).font(.headline)
                Text(L10n.t(.tokenUsageCaption))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            Divider()

            if store.records.isEmpty {
                ContentUnavailableView(
                    L10n.t(.tokenNoData),
                    systemImage: "number.circle",
                    description: Text(L10n.t(.tokenNoDataCaption))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section(L10n.t(.tokenCumulative)) {
                        usageRows(total)
                    }
                    Section(L10n.t(.tokenRecent)) {
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
                Text(L10n.t(.tokenRecordCount, store.records.count))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t(.clearRecords), role: .destructive) { store.clear() }
                    .disabled(store.records.isEmpty)
            }
            .padding(12)
        }
        .frame(minWidth: 560, minHeight: 460)
    }

    @ViewBuilder
    private func usageRows(_ usage: TokenUsage) -> some View {
        row(L10n.t(.tokenInput), usage.inputTokens)
        row(L10n.t(.tokenCachedInput), usage.cachedInputTokens)
        row(L10n.t(.tokenOutput), usage.outputTokens)
        row(L10n.t(.tokenReasoning), usage.reasoningTokens)
        row(L10n.t(.tokenAudioInput), usage.audioInputTokens)
        row(L10n.t(.tokenAudioOutput), usage.audioOutputTokens)
        if let seconds = usage.audioSeconds {
            HStack {
                Text(L10n.t(.tokenAudioDuration))
                Spacer()
                Text(String(format: L10n.language == .japanese ? "%.1f 秒" : "%.1f s", seconds)).monospacedDigit()
            }
        }
        row(L10n.t(.tokenTotal), usage.totalTokens)
    }

    private func row(_ title: String, _ value: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value.formatted()).monospacedDigit()
        }
    }
}
