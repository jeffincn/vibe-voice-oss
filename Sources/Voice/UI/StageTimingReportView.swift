import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct StageTimingReportView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        StageTimingReportContent(store: appState.stageTiming)
    }
}

private struct StageTimingReportContent: View {
    @ObservedObject var store: StageTimingStore
    @State private var exportMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    L10n.t(.timingNoRecords),
                    systemImage: "stopwatch",
                    description: Text(L10n.t(.timingNoRecordsCaption))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.sessions) { session in
                        sessionSection(session)
                    }
                }
                .listStyle(.inset)
            }
            Divider()
            footer
        }
        .frame(minWidth: 520, minHeight: 420)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t(.timingHeader))
                    .font(.headline)
                if let latest = store.latestSession {
                    Text(L10n.t(.timingLatest, latest.formattedTotal, latest.outcome.label))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L10n.t(.timingDescription))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.hasActiveSession {
                Label(L10n.t(.timingActive), systemImage: "circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
    }

    private func sessionSection(_ session: PipelineRunReport) -> some View {
        Section {
            ForEach(session.stages) { stage in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stage.stage.label)
                        if let detail = stage.detail {
                            Text(detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(StageTimingFormatter.formatMs(stage.durationMs))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text(StageTimingFormatter.displayString(from: session.startedAt))
                Spacer()
                Text(session.outcome.label)
                Text("·")
                Text(session.formattedTotal)
                if let target = session.promptTarget {
                    Text("· \(target)")
                }
            }
            .font(.caption)
            .textCase(nil)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(L10n.t(.exportCSV)) { export(.csv) }
                .disabled(store.sessions.isEmpty)
            Button(L10n.t(.exportHTML)) { export(.html) }
                .disabled(store.sessions.isEmpty)
            Button(L10n.t(.clearRecords), role: .destructive) {
                store.clearHistory()
                exportMessage = ""
            }
            .disabled(store.sessions.isEmpty)
            Spacer()
            Text(exportMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
    }

    private enum ExportKind {
        case csv
        case html

        var title: String {
            switch self {
            case .csv: L10n.t(.exportTimingCSV)
            case .html: L10n.t(.exportTimingHTML)
            }
        }

        var filename: String {
            let stamp = StageTimingFormatter.displayString(from: Date())
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "-")
            switch self {
            case .csv: return "vibe-voice-oss-stage-timing-\(stamp).csv"
            case .html: return "vibe-voice-oss-stage-timing-\(stamp).html"
            }
        }

        var contentType: UTType {
            switch self {
            case .csv: .commaSeparatedText
            case .html: .html
            }
        }
    }

    private func export(_ kind: ExportKind) {
        let content: String
        switch kind {
        case .csv: content = store.exportCSV()
        case .html: content = store.exportHTML()
        }

        let panel = NSSavePanel()
        panel.title = kind.title
        panel.nameFieldStringValue = kind.filename
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [kind.contentType]
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else {
            exportMessage = L10n.t(.exportCancelled)
            return
        }

        do {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            exportMessage = L10n.t(.exportSuccess, url.lastPathComponent)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportMessage = L10n.t(.exportFailed, error.localizedDescription)
        }
    }
}
