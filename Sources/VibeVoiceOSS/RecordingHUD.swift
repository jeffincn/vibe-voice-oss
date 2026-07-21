import AppKit
import SwiftUI

@MainActor
final class RecordingHUDController {
    private let panel: RecordingPanel
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
        panel = RecordingPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        // Needed so NSVisualEffectView (.behindWindow) can blur the desktop behind the HUD.
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        // Allow the stop button to receive clicks.
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        if #available(macOS 26, *) {
            panel.appearance = NSAppearance(named: .darkAqua)
        }
        panel.contentView = RecordingHostingView(
            rootView: RecordingHUDView(
                onStop: { [weak self] in
                    self?.appState?.cancelActiveSession()
                },
                onCopy: { [weak self] in
                    self?.appState?.copyPartialTranscript()
                }
            ).environmentObject(appState)
        )
    }

    func show() {
        // Fit panel to current content height before placing, so the waveform stays on-screen.
        syncPanelSize()
        positionOnActiveScreen()
        // Already visible: refresh layout only. Re-fading alpha→0 causes endless HUD flashing
        // when Voice Pipeline re-enters `.listening` after every VAD/ASR state tick.
        if panel.isVisible, panel.alphaValue > 0.9 {
            return
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1)
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 1, 0.5, 1)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak panel] in
            Task { @MainActor in panel?.orderOut(nil) }
        })
    }

    /// Keep AppKit panel bounds in sync with the SwiftUI HUD layout.
    private func syncPanelSize() {
        let showingCaption: Bool = {
            guard let appState else { return true }
            switch appState.phase {
            case .recording, .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing:
                return true
            case .success, .failed, .idle:
                return !appState.partialTranscript.isEmpty
            }
        }()
        let size = NSSize(width: 640, height: showingCaption ? 380 : 220)
        var frame = panel.frame
        frame.size = size
        panel.setFrame(frame, display: false)
    }

    private func positionOnActiveScreen() {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        // Keep the waveform / stop controls clear of the dock and screen bottom.
        // Previously minY+42 left the lower pill hanging off short displays.
        let bottomMargin = max(120, floor(visibleFrame.height * 0.10))
        let sideMargin: CGFloat = 16
        let topMargin: CGFloat = 16

        var origin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + bottomMargin
        )

        let maxY = visibleFrame.maxY - panel.frame.height - topMargin
        origin.y = min(max(origin.y, visibleFrame.minY + sideMargin), maxY)
        origin.x = min(
            max(origin.x, visibleFrame.minX + sideMargin),
            visibleFrame.maxX - panel.frame.width - sideMargin
        )

        panel.setFrameOrigin(origin)
    }
}

private final class RecordingPanel: NSPanel {
    /// Keep the frontmost text field focused; NSButton still receives clicks on a nonactivating panel.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Click-through for empty HUD chrome; stop button and caption scroll absorb hits.
private final class RecordingHostingView<Content: View>: NSHostingView<Content> {
    /// Without this, AppKit treats the hosting view as opaque and vibrancy/glass never shows.
    override var isOpaque: Bool { false }

    required init(rootView: Content) {
        super.init(rootView: rootView)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
        window?.isOpaque = false
        window?.backgroundColor = .clear
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var node: NSView? = hit
        while let current = node, current !== self {
            if current is NSControl || current is NSScrollView {
                return current is NSControl ? current : hit
            }
            node = current.superview
        }
        return nil
    }
}

/// AppKit button so clicks work on a floating nonactivating HUD panel.
private final class HUDCircleButtonView: NSButton {
    var side: CGFloat = 60 {
        didSet { invalidateIntrinsicContentSize() }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: side, height: side)
    }

    /// First click on an inactive/nonactivating panel must still fire the action.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct HUDStopNSButton: NSViewRepresentable {
    var size: CGFloat
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> HUDCircleButtonView {
        let button = HUDCircleButtonView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        button.side = size
        button.title = ""
        button.image = NSImage(
            systemSymbolName: "stop.fill",
            accessibilityDescription: L10n.t(.stopAndCancel)
        )
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryChange)
        button.contentTintColor = .white
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.92).cgColor
        button.layer?.cornerRadius = size / 2
        button.layer?.borderWidth = 1
        button.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        button.toolTip = L10n.t(.stopAndCancel)
        button.setAccessibilityLabel(L10n.t(.stopAndCancel))
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        button.sendAction(on: .leftMouseUp)
        return button
    }

    func updateNSView(_ button: HUDCircleButtonView, context: Context) {
        context.coordinator.action = action
        button.side = size
        button.layer?.cornerRadius = size / 2
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        @objc func clicked(_ sender: Any?) {
            action()
        }
    }
}

/// Invisible AppKit hit target — Liquid Glass chrome sits underneath; this
/// receives first-click on a nonactivating panel without swallowing hover samples.
private struct HUDGlassHitNSButton: NSViewRepresentable {
    var size: CGFloat
    var enabled: Bool
    var accessibilityLabel: String
    var action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> HUDCircleButtonView {
        let button = HUDCircleButtonView(frame: NSRect(x: 0, y: 0, width: size, height: size))
        button.side = size
        button.title = ""
        button.image = nil
        button.imagePosition = .imageOnly
        button.isBordered = false
        button.bezelStyle = .inline
        button.setButtonType(.momentaryChange)
        button.focusRingType = .none
        button.wantsLayer = true
        button.layer?.backgroundColor = NSColor.clear.cgColor
        button.alphaValue = 0.01
        button.target = context.coordinator
        button.action = #selector(Coordinator.clicked(_:))
        button.sendAction(on: .leftMouseUp)
        button.isEnabled = enabled
        button.setAccessibilityLabel(accessibilityLabel)
        button.toolTip = accessibilityLabel
        return button
    }

    func updateNSView(_ button: HUDCircleButtonView, context: Context) {
        context.coordinator.action = action
        button.side = size
        button.isEnabled = enabled
        button.setAccessibilityLabel(accessibilityLabel)
        button.toolTip = accessibilityLabel
    }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        @objc func clicked(_ sender: Any?) {
            action()
        }
    }
}

/// Secondary dock control: Liquid Glass circle that morphs clipboard → checkmark.
private struct HUDDockCopyButton: View {
    var size: CGFloat
    var enabled: Bool
    var reduceMotion: Bool
    var action: () -> Void

    @State private var showCopied = false
    @State private var pressFlash = false
    @State private var resetTask: Task<Void, Never>?

    private var morphAnimation: Animation? {
        reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.32)
    }

    var body: some View {
        ZStack {
            glassPlate

            // Press highlight flash (dynamic feedback).
            Circle()
                .fill(Color.white.opacity(pressFlash ? 0.18 : 0))
                .allowsHitTesting(false)

            glyph

            HUDGlassHitNSButton(
                size: size,
                enabled: enabled,
                accessibilityLabel: showCopied ? L10n.t(.copied) : L10n.t(.copyCurrentText),
                action: triggerCopy
            )
        }
        .frame(width: size, height: size)
        .scaleEffect(pressFlash ? 0.92 : (showCopied ? 1.04 : 1.0))
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
        .opacity(enabled ? 1 : 0.38)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: enabled)
        .accessibilityLabel(showCopied ? L10n.t(.copied) : L10n.t(.copyCurrentText))
        .accessibilityHint(L10n.t(.copyAccessibilityHint))
        .accessibilityAddTraits(.isButton)
        .onDisappear {
            resetTask?.cancel()
            resetTask = nil
        }
    }

    @ViewBuilder
    private var glassPlate: some View {
        if #available(macOS 26, *) {
            Color.clear
                .frame(width: size, height: size)
                .glassEffect(.regular.interactive(), in: .circle)
                .overlay { glassRim }
                .overlay { glassInnerShadow }
        } else {
            ZStack {
                HUDFrostedGlass(cornerRadius: size / 2)
                    .frame(width: size, height: size)

                // Adaptive dark tint so glyphs stay legible on light desktops.
                Circle()
                    .fill(Color(red: 0.12, green: 0.11, blue: 0.10).opacity(0.28))
                    .allowsHitTesting(false)

                Circle()
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: Color.white.opacity(0.16), location: 0),
                                .init(color: Color.white.opacity(0.04), location: 0.4),
                                .init(color: Color.clear, location: 0.72),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(1)
                    .allowsHitTesting(false)

                glassRim
                glassInnerShadow
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        }
    }

    /// Double-edge refraction rim (outer highlight + inner cool edge).
    private var glassRim: some View {
        ZStack {
            Circle()
                .strokeBorder(
                    LinearGradient(
                        stops: [
                            .init(color: Color.white.opacity(0.48), location: 0),
                            .init(color: Color.white.opacity(0.14), location: 0.35),
                            .init(color: Color.white.opacity(0.05), location: 0.65),
                            .init(color: Color.black.opacity(0.22), location: 1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                .padding(1.5)
        }
        .allowsHitTesting(false)
    }

    private var glassInnerShadow: some View {
        Circle()
            .stroke(Color.black.opacity(0.3), lineWidth: 3)
            .blur(radius: 2.4)
            .mask(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .allowsHitTesting(false)
    }

    private var glyph: some View {
        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
            .font(.system(size: size * 0.34, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(showCopied ? 0.98 : 0.92))
            .symbolRenderingMode(.monochrome)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .allowsHitTesting(false)
    }

    private func triggerCopy() {
        guard enabled else { return }
        action()
        resetTask?.cancel()

        if reduceMotion {
            pressFlash = false
            showCopied = true
        } else {
            withAnimation(.easeOut(duration: 0.08)) {
                pressFlash = true
            }
            withAnimation(morphAnimation) {
                showCopied = true
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(90))
                withAnimation(.spring(duration: 0.22, bounce: 0.28)) {
                    pressFlash = false
                }
            }
        }

        resetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            withAnimation(morphAnimation) {
                showCopied = false
            }
        }
    }
}

/// Native macOS frosted plate. Keep the effect fully opaque: reducing alpha fades
/// the blur itself and produces transparent "paper" instead of frosted glass.
private final class HUDFrostedGlassView: NSVisualEffectView {
    var cornerRadius: CGFloat = 28 {
        didSet { applyChrome() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // HUD material is the most translucent behind-window blur Apple ships —
        // dark appearance only tints lightly so wallpaper / app colors still
        // refract through (Codex-style tea glass), not a solid charcoal slab.
        material = .hudWindow
        blendingMode = .behindWindow
        state = .active
        isEmphasized = false
        appearance = NSAppearance(named: .vibrantDark)
        wantsLayer = true
        applyChrome()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func applyChrome() {
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.isOpaque = false
    }
}

private struct HUDFrostedGlass: NSViewRepresentable {
    var cornerRadius: CGFloat
    var intensity: CGFloat = 1.0

    func makeNSView(context: Context) -> HUDFrostedGlassView {
        let view = HUDFrostedGlassView(frame: .zero)
        view.cornerRadius = cornerRadius
        view.alphaValue = intensity
        return view
    }

    func updateNSView(_ view: HUDFrostedGlassView, context: Context) {
        view.cornerRadius = cornerRadius
        view.state = .active
        view.alphaValue = intensity
    }
}

private struct RecordingHUDView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onStop: () -> Void
    let onCopy: () -> Void

    /// Nine waveform bars inside the input pill (Typeless hero reference).
    /// Idle = equal dots; speaking = stretch into capsule bars with a center peak.
    private let barCount = 9
    private let barWidth: CGFloat = 8
    private let barSpacing: CGFloat = 6
    /// Waveform capsule — Option C dock (240–280pt).
    private let pillHeight: CGFloat = 60
    private let pillWidth: CGFloat = 260
    private let pillBarInset: CGFloat = 10
    /// Secondary Copy is intentionally smaller than primary Stop.
    private let copyButtonSize: CGFloat = 50
    private let stopButtonSize: CGFloat = 60
    /// Live caption shows up to 3 lines; overflow scrolls.
    private let captionLineCount = 3
    private let captionFontSize: CGFloat = 16
    private var captionLineHeight: CGFloat { captionFontSize * 1.35 }
    private var captionBodyHeight: CGFloat { captionLineHeight * CGFloat(captionLineCount) }
    /// Extra inset so soft shadows are not clipped by the panel bounds.
    private let shadowBleed: CGFloat = 36

    var body: some View {
        let _ = appState.settings.uiLanguageID
        let phase = appState.phase
        let primary = appState.settings.effectiveVoicePipelineEnabled
            ? phase.pipelineHUDPrimary
            : phase.hudPrimary
        let secondary = appState.hudSecondary
        let bands = appState.audioBands
        let level = max(appState.audioLevel, bands.overall)
        let partial = appState.partialTranscript
        let stable = appState.stableTranscript
        let showDisplay = shouldShowDisplay(phase: phase, partial: partial)
        let canCopy = !partial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        glassRoot {
            VStack(spacing: 14) {
                if showDisplay {
                    displayBubble(
                        partial: partial,
                        stable: stable,
                        primary: primary,
                        secondary: secondary,
                        phase: phase
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
                }

                // Option C: waveform | Copy 50pt | Stop 60pt
                HStack(spacing: 12) {
                    TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { timeline in
                        let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                        let activity = Self.activity(from: level)
                        waveformPill(phase: phase, activity: activity, bands: bands, time: time)
                    }

                    if showsStopButton(phase: phase) {
                        if canCopy {
                            HUDDockCopyButton(
                                size: copyButtonSize,
                                enabled: true,
                                reduceMotion: reduceMotion,
                                action: onCopy
                            )
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .scale(scale: 0.86)),
                                    removal: .opacity.combined(with: .scale(scale: 0.9))
                                )
                            )
                        }

                        stopButton
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: canCopy)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showDisplay)
        .frame(width: 520)
        .padding(.vertical, 10)
        .padding(shadowBleed)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel(primary: primary, secondary: secondary, phase: phase, partial: partial))
        .frame(width: 640, height: showDisplay ? 380 : 220)
    }

    @ViewBuilder
    private func glassRoot<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 26, *) {
            GlassEffectContainer {
                content()
            }
            .environment(\.colorScheme, .dark)
        } else {
            content()
        }
    }

    private func showsStopButton(phase: AppState.Phase) -> Bool {
        switch phase {
        case .recording, .finalizing, .transcribing, .structuring, .translating, .optimizing:
            true
        default:
            false
        }
    }

    private var stopButton: some View {
        HUDStopNSButton(size: stopButtonSize, action: onStop)
            .frame(width: stopButtonSize, height: stopButtonSize)
            .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
            .accessibilityHint(L10n.t(.stopAccessibilityHint))
    }

    private func shouldShowDisplay(phase: AppState.Phase, partial: String) -> Bool {
        switch phase {
        case .recording, .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing:
            return true
        case .success, .failed:
            return !partial.isEmpty
        case .idle:
            return !partial.isEmpty
        }
    }

    // MARK: - Display (glass text bubble)

    private func displayTextContent(
        display: String,
        waiting: Bool,
        stable: String,
        primary: String,
        secondary: String?,
        phase: AppState.Phase,
        showStatusChrome: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showStatusChrome {
                TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1.0 / 20.0, paused: reduceMotion)) { timeline in
                    let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                    let status = statusCaption(phase: phase, time: time, primary: primary, secondary: secondary)
                    statusHeader(text: status, phase: phase, time: time)
                }
            }

            if waiting {
                if !showStatusChrome {
                    Text(statusCaption(phase: phase, time: 0, primary: primary, secondary: secondary))
                        .font(.system(size: captionFontSize, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.7))
                        .lineLimit(captionLineCount)
                        .frame(maxWidth: .infinity, minHeight: captionBodyHeight, maxHeight: captionBodyHeight, alignment: .topLeading)
                } else {
                    Text(waitingBodyHint(phase: phase))
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(captionLineCount)
                        .frame(maxWidth: .infinity, minHeight: captionBodyHeight, maxHeight: captionBodyHeight, alignment: .topLeading)
                }
            } else {
                subtitleText(partial: display, stable: stable)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func displayBubble(
        partial: String,
        stable: String,
        primary: String,
        secondary: String?,
        phase: AppState.Phase
    ) -> some View {
        let display = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        let waiting = display.isEmpty
        let showStatusChrome = shouldShowStatusChrome(phase: phase)

        if #available(macOS 26, *) {
            displayTextContent(
                display: display, waiting: waiting, stable: stable,
                primary: primary, secondary: secondary,
                phase: phase, showStatusChrome: showStatusChrome
            )
            .glassEffect(
                .regular.interactive(),
                in: .rect(cornerRadius: 32)
            )
        } else {
            let glassShape = RoundedRectangle(cornerRadius: 32, style: .continuous)

            ZStack {
                glassShape
                    .fill(Color.black.opacity(0.001))
                    .shadow(color: Color.black.opacity(0.28), radius: 40, y: 18)

                HUDFrostedGlass(cornerRadius: 32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay {
                        glassShape
                            .fill(Color(red: 0.18, green: 0.14, blue: 0.10).opacity(0.18))
                            .allowsHitTesting(false)
                    }
                    .overlay {
                        glassShape
                            .fill(
                                LinearGradient(
                                    stops: [
                                        .init(color: Color.white.opacity(0.10), location: 0),
                                        .init(color: Color.white.opacity(0.02), location: 0.35),
                                        .init(color: Color.clear, location: 0.7),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .allowsHitTesting(false)
                    }

                displayTextContent(
                    display: display, waiting: waiting, stable: stable,
                    primary: primary, secondary: secondary,
                    phase: phase, showStatusChrome: showStatusChrome
                )
            }
        }
    }

    /// Show an explicit status chrome for processing / outcome phases (and recording).
    private func shouldShowStatusChrome(phase: AppState.Phase) -> Bool {
        switch phase {
        case .recording, .finalizing, .transcribing, .structuring, .translating, .optimizing, .routing, .success, .failed:
            return true
        case .idle:
            return false
        }
    }

    private func statusHeader(text: String, phase: AppState.Phase, time: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusDotColor(phase: phase))
                .frame(width: 7, height: 7)
                .opacity(statusDotOpacity(phase: phase, time: time))

            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(statusTitleColor(phase: phase))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if appState.transcriptCopied {
                copiedToastChip
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.88, anchor: .trailing)),
                            removal: .opacity
                        )
                    )
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.25, bounce: 0.28), value: appState.transcriptCopied)
        .accessibilityAddTraits(.updatesFrequently)
    }

    /// Compact success chip — matches the design’s “已复制” toast on the caption pane.
    private var copiedToastChip: some View {
        Text(L10n.t(.copied))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                if #available(macOS 26, *) {
                    Capsule(style: .continuous)
                        .fill(Color.clear)
                        .glassEffect(.regular.tint(.green.opacity(0.35)).interactive(), in: .capsule)
                } else {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.72))
                        .overlay {
                            Capsule(style: .continuous)
                                .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
                        }
                }
            }
            .accessibilityHidden(true)
    }

    private func statusDotColor(phase: AppState.Phase) -> Color {
        switch phase {
        case .recording:
            return Color.red.opacity(0.95)
        case .failed:
            return Color.orange.opacity(0.95)
        case .success:
            return Color.green.opacity(0.9)
        default:
            return Color.white.opacity(0.55)
        }
    }

    private func statusDotOpacity(phase: AppState.Phase, time: TimeInterval) -> Double {
        switch phase {
        case .recording:
            return reduceMotion ? 1 : (0.45 + 0.55 * ((sin(time * 3.2) + 1) / 2))
        case .finalizing, .transcribing, .structuring, .translating, .optimizing:
            return reduceMotion ? 0.85 : (0.4 + 0.6 * ((sin(time * 4.0) + 1) / 2))
        default:
            return 1
        }
    }

    private func statusTitleColor(phase: AppState.Phase) -> Color {
        switch phase {
        case .failed:
            return Color.orange.opacity(0.95)
        case .success:
            return Color.white.opacity(0.85)
        default:
            return Color.white.opacity(0.85)
        }
    }

    private func statusCaption(
        phase: AppState.Phase,
        time: TimeInterval,
        primary: String,
        secondary: String?
    ) -> String {
        if let secondary, !secondary.isEmpty, !primary.isEmpty {
            return "\(primary) · \(secondary)"
        }
        switch phase {
        case .recording:
            let dots = String(repeating: ".", count: Int(time * 2) % 3 + 1)
            return primary.isEmpty ? "\(L10n.t(.hudListening))\(dots)" : "\(primary)\(dots)"
        case .finalizing:
            return primary.isEmpty ? L10n.t(.phaseFinalizing) : primary
        case .transcribing:
            return primary.isEmpty ? L10n.t(.phaseTranscribing) : primary
        case .structuring:
            return primary.isEmpty ? L10n.t(.phaseStructuring) : primary
        case .translating:
            return primary.isEmpty ? L10n.t(.phaseTranslating) : primary
        case .optimizing:
            return primary.isEmpty ? L10n.t(.phaseOptimizing) : primary
        case .routing:
            return primary.isEmpty ? L10n.t(.phaseRouting) : primary
        case .success:
            return primary.isEmpty ? L10n.t(.success) : primary
        case .failed:
            return primary.isEmpty ? L10n.t(.failed) : primary
        case .idle:
            return primary.isEmpty ? "…" : primary
        }
    }

    private func waitingBodyHint(phase: AppState.Phase) -> String {
        switch phase {
        case .recording:
            return L10n.t(.hudWaitingSpeak)
        case .finalizing:
            return L10n.t(.hudWaitingFinalizing)
        case .transcribing:
            return L10n.t(.hudWaitingTranscribing)
        case .structuring:
            return L10n.t(.hudWaitingStructuring)
        case .translating:
            return L10n.t(.hudWaitingTranslating)
        case .optimizing:
            return L10n.t(.hudWaitingOptimizing)
        case .routing:
            return L10n.t(.hudWaitingRouting)
        case .failed:
            return L10n.t(.hudWaitingFailed)
        case .success:
            return L10n.t(.hudWaitingSuccess)
        case .idle:
            return "…"
        }
    }

    /// Up to 3 lines of live caption; longer text scrolls (newest stays in view).
    private func subtitleText(partial: String, stable: String) -> some View {
        let unstable: String
        if !stable.isEmpty, partial.hasPrefix(stable) {
            unstable = String(partial.dropFirst(stable.count))
        } else {
            unstable = ""
        }

        let stablePart = stable.isEmpty || !partial.hasPrefix(stable) ? partial : stable
        let stableVisible = stablePart
        let unstableVisible = unstable

        return ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                (Text(stableVisible)
                    .foregroundColor(Color.white.opacity(0.95))
                + Text(unstableVisible)
                    .foregroundColor(Color.white.opacity(0.5)))
                    .font(.system(size: captionFontSize, weight: .medium, design: .rounded))
                    .lineSpacing(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .id("caption-bottom")
            }
            .scrollContentBackground(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .background(Color.clear)
            .frame(height: captionBodyHeight, alignment: .top)
            .clipped()
            .onChange(of: partial) { _, _ in
                if reduceMotion {
                    proxy.scrollTo("caption-bottom", anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.12)) {
                        proxy.scrollTo("caption-bottom", anchor: .bottom)
                    }
                }
            }
            .onAppear {
                proxy.scrollTo("caption-bottom", anchor: .bottom)
            }
        }
        .contentTransition(.interpolate)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: partial)
    }

    // MARK: - Input (pill + 9-bar waveform)

    private func waveformBars(
        phase: AppState.Phase,
        activity: CGFloat,
        bands: AudioBands,
        time: TimeInterval
    ) -> some View {
        HStack(spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                let height = barHeight(
                    index: index,
                    time: time,
                    phase: phase,
                    activity: activity,
                    bands: bands
                )
                Capsule(style: .continuous)
                    .fill(barFill(phase: phase, activity: activity))
                    .frame(width: barWidth, height: height)
                    .opacity(barOpacity(phase: phase, activity: activity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
        .padding(.vertical, pillBarInset)
        .frame(width: pillWidth, height: pillHeight)
    }

    @ViewBuilder
    private func waveformPill(
        phase: AppState.Phase,
        activity: CGFloat,
        bands: AudioBands,
        time: TimeInterval
    ) -> some View {
        if #available(macOS 26, *) {
            waveformBars(phase: phase, activity: activity, bands: bands, time: time)
                .glassEffect(.regular.interactive(), in: .capsule)
        } else {
            waveformBars(phase: phase, activity: activity, bands: bands, time: time)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.92))
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(Color.white.opacity(0.14), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 4)
                )
                .clipShape(Capsule(style: .continuous))
        }
    }

    /// Symmetric mountain envelope matching the reference (center tallest, outer ends as dots).
    private func waveformEnvelope(index: Int) -> CGFloat {
        let center = CGFloat(barCount - 1) / 2
        let distance = abs(CGFloat(index) - center) / center
        return CGFloat(pow(Double(cos(distance * .pi / 2)), 1.35))
    }

    /// Idle / quiet: equal dots. Active: stretch into 9 capsule bars.
    /// Heights are clamped so bars never punch through the black capsule.
    private func barHeight(
        index: Int,
        time: TimeInterval,
        phase: AppState.Phase,
        activity: CGFloat,
        bands: AudioBands
    ) -> CGFloat {
        let base = barWidth
        let maxStretch = pillHeight - (pillBarInset * 2)

        func clamped(_ value: CGFloat) -> CGFloat {
            min(maxStretch, max(base, value))
        }

        if reduceMotion {
            let band = bandActivity(index: index, bands: bands, phase: phase)
            let quiet = phase.drivesLiveAudioVisual ? activity : 0.12
            let shape = waveformEnvelope(index: index)
            return clamped(base + (maxStretch - base) * min(1, (quiet * 0.55 + band * 0.35) * shape))
        }

        switch phase {
        case .recording:
            let shape = waveformEnvelope(index: index)
            let band = bandActivity(index: index, bands: bands, phase: phase)
            let wave = CGFloat(sin(time * 10.8 + Double(index) * 0.85))
            let traveling = CGFloat(sin(time * 6.6 - Double(index) * 0.55))
            let driven = activity * 0.78 + band * 0.5
            let wobble = (0.06 + activity * 0.16) * wave + traveling * 0.05 * activity
            let amount = min(1, max(0, driven * (0.35 + shape * 0.9) + wobble * shape))
            // Near silence → gray dots; voice → mountain waveform.
            if activity < 0.08 && band < 0.06 {
                let nudge = CGFloat(sin(time * 3.2 + Double(index) * 0.7)) * 0.5
                return clamped(base + max(0, nudge))
            }
            return clamped(base + (maxStretch - base) * amount)

        case .finalizing, .transcribing, .structuring, .translating, .optimizing:
            let pulse = CGFloat((sin(time * 5.2 - Double(index) * 0.7) + 1) / 2)
            let shape = waveformEnvelope(index: index)
            return clamped(base + (maxStretch - base) * (0.08 + pulse * 0.28 * (0.45 + shape * 0.55)))

        default:
            return base
        }
    }

    private func barFill(phase: AppState.Phase, activity: CGFloat) -> Color {
        switch phase {
        case .recording:
            let brightness = 0.55 + Double(activity) * 0.45
            return Color.white.opacity(brightness)
        case .finalizing, .transcribing, .structuring, .translating, .optimizing:
            return Color.white.opacity(0.7)
        default:
            return Color.white.opacity(0.5)
        }
    }

    private func barOpacity(phase: AppState.Phase, activity: CGFloat) -> Double {
        switch phase {
        case .recording:
            return 0.82 + Double(activity) * 0.18
        default:
            return 0.9
        }
    }

    private func phaseID(_ phase: AppState.Phase) -> String {
        switch phase {
        case .idle: "idle"
        case .recording: "recording"
        case .finalizing: "finalizing"
        case .transcribing: "transcribing"
        case .structuring: "structuring"
        case .translating: "translating"
        case .optimizing: "optimizing"
        case .routing: "routing"
        case .success: "success"
        case .failed: "failed"
        }
    }

    private static func activity(from level: Float) -> CGFloat {
        let gated = max(0, min(1, (CGFloat(level) - 0.01) / 0.38))
        return pow(gated, 0.55)
    }

    private func bandActivity(index: Int, bands: AudioBands, phase: AppState.Phase) -> CGFloat {
        guard phase.drivesLiveAudioVisual else { return 0 }
        let t = Double(index) / Double(max(barCount - 1, 1))
        let value: Float
        if t < 0.28 {
            value = bands.lowMid
        } else if t < 0.55 {
            value = bands.mid
        } else if t < 0.78 {
            value = max(bands.mid, bands.high)
        } else {
            value = bands.overall
        }
        return CGFloat(value)
    }

    private func accessibilityLabel(
        primary: String,
        secondary: String?,
        phase: AppState.Phase,
        partial: String
    ) -> String {
        var parts: [String] = []
        if let secondary {
            parts.append("\(primary)，\(secondary)")
        } else if phase == .recording {
            parts.append(L10n.t(.phaseRecording))
        } else if !primary.isEmpty {
            parts.append(primary)
        } else {
            parts.append("Vibe Voice OSS")
        }
        if !partial.isEmpty {
            parts.append(partial)
        }
        return parts.joined(separator: "。")
    }
}
