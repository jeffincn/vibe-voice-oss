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
                    "暂无耗时记录",
                    systemImage: "stopwatch",
                    description: Text("完成一次录音转写后，各阶段耗时会出现在这里。")
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
                Text("阶段耗时报告")
                    .font(.headline)
                if let latest = store.latestSession {
                    Text("最近一次合计 \(latest.formattedTotal) · \(latest.outcome.label)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("记录每次录音后的转写 / 整理 / 翻译 / Prompt 编译耗时")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.hasActiveSession {
                Label("计时中", systemImage: "circle.fill")
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
            Button("导出 CSV…") { export(.csv) }
                .disabled(store.sessions.isEmpty)
            Button("导出 HTML…") { export(.html) }
                .disabled(store.sessions.isEmpty)
            Button("清空记录", role: .destructive) {
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
            case .csv: "导出阶段耗时 CSV"
            case .html: "导出阶段耗时 HTML"
            }
        }

        var filename: String {
            let stamp = StageTimingFormatter.displayString(from: Date())
                .replacingOccurrences(of: ":", with: "-")
                .replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "/", with: "-")
            switch self {
            case .csv: return "vibe-voice-stage-timing-\(stamp).csv"
            case .html: return "vibe-voice-stage-timing-\(stamp).html"
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
            exportMessage = "已取消导出"
            return
        }

        do {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
            exportMessage = "已导出：\(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            exportMessage = "导出失败：\(error.localizedDescription)"
        }
    }
}
