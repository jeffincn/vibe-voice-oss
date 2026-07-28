import AppKit
import SwiftUI

/// Top-right frosted banner after a successful transcription output.
@MainActor
final class ResultBannerController {
    private let panel: ResultBannerPanel
    private weak var appState: AppState?
    private var dismissTask: Task<Void, Never>?
    private let bannerWidth: CGFloat = 380
    private let bannerHeight: CGFloat = 168

    init(appState: AppState) {
        self.appState = appState
        panel = ResultBannerPanel(
            contentRect: NSRect(x: 0, y: 0, width: bannerWidth, height: bannerHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(
            rootView: ResultBannerView(
                onCopy: { [weak self] in self?.appState?.copyLastTranscript() },
                onReformat: { [weak self] in self?.appState?.reformatLastTranscript() },
                onSelectRole: { [weak self] role in self?.appState?.rerunLastTranscript(using: role) },
                onDismiss: { [weak self] in self?.hide() }
            )
            .environmentObject(appState)
        )
    }

    func show(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        dismissTask?.cancel()
        positionOnActiveScreen()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = 1
        }
        scheduleAutoDismiss()
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            Task { @MainActor in panel?.orderOut(nil) }
        })
    }

    private func scheduleAutoDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(12))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func positionOnActiveScreen() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }
        let margin: CGFloat = 14
        panel.setFrame(
            NSRect(
                x: visibleFrame.maxX - bannerWidth - margin,
                y: visibleFrame.maxY - bannerHeight - margin,
                width: bannerWidth,
                height: bannerHeight
            ),
            display: true
        )
    }
}

private final class ResultBannerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private enum BannerChrome {
    /// Keep these identifiers/labels exactly as specified.
    static let copyButtonTitle = "复制按钮"
    static let reformatButtonTitle = "重新整理嘅按钮"
}

private struct ResultBannerView: View {
    @EnvironmentObject private var appState: AppState
    let onCopy: () -> Void
    let onReformat: () -> Void
    let onSelectRole: (RoleProfile?) -> Void
    let onDismiss: () -> Void

    private var preview: String {
        let text = appState.lastTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return L10n.t(.recognitionComplete) }
        if text.count <= 120 { return text }
        return String(text.prefix(120)) + "…"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                appIcon
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Vibe Voice OSS")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(L10n.t(.justNow))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(L10n.t(.close))
                    }
                    Text(preview)
                        .font(.system(size: 12))
                        .foregroundStyle(.primary.opacity(0.88))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if appState.settings.roleModeEnabled {
                        Menu {
                            Button("自动判定") { onSelectRole(nil) }
                            ForEach(appState.settings.activeRoleCandidates) { role in
                                Button(role.name) { onSelectRole(role) }
                            }
                        } label: {
                            Label(
                                appState.settings.lockedRole?.name ?? "自动判定角色",
                                systemImage: appState.settings.lockedRole?.symbol ?? "person.3.fill"
                            )
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }

            HStack(spacing: 8) {
                actionButton(
                    title: appState.transcriptCopied ? L10n.t(.copied) : L10n.t(.copyButtonTitle),
                    systemImage: appState.transcriptCopied ? "checkmark" : "doc.on.doc",
                    emphasized: false,
                    action: onCopy
                )
                .accessibilityIdentifier(BannerChrome.copyButtonTitle)

                actionButton(
                    title: L10n.t(.reformatButtonTitle),
                    systemImage: "arrow.triangle.2.circlepath",
                    emphasized: true,
                    action: onReformat
                )
                .accessibilityIdentifier(BannerChrome.reformatButtonTitle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 380, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
        }
        .padding(4)
    }

    private var appIcon: some View {
        Group {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 36, height: 36)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor)
                    )
            }
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        emphasized: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .padding(.horizontal, 8)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(emphasized ? Color.accentColor.opacity(0.9) : Color.primary.opacity(0.08))
                }
                .foregroundStyle(emphasized ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .disabled(appState.lastTranscript.isEmpty || appState.phase.isBusy)
    }
}
