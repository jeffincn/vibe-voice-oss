import AppKit

/// Tiny tag HUD at the caret that plays a 中 ↔ EN cross-fade slide when
/// ascii_mode flips (Shift tap, Caps Lock, Ctrl+Shift+2, …).
@MainActor
final class ModeSwitchHUD {
    static let shared = ModeSwitchHUD()

    private let panel: NSPanel
    private let chrome = NSView()
    private let outgoingTag = TagView()
    private let incomingTag = TagView()
    private var hideWork: DispatchWorkItem?

    private let tagSize = NSSize(width: 36, height: 26)
    private let slide: CGFloat = 22
    private let duration: TimeInterval = 0.42

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 72, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Same shielding level as CandidateBarWindow so the 中/EN tag is not
        // buried under Cursor-style floating composers.
        panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.ignoresMouseEvents = true

        chrome.wantsLayer = true
        chrome.layer?.masksToBounds = false
        panel.contentView = chrome

        for tag in [outgoingTag, incomingTag] {
            tag.wantsLayer = true
            chrome.addSubview(tag)
        }
    }

    /// `toEnglish == true` means we just entered ASCII mode (中 → EN).
    func play(toEnglish: Bool, anchor: NSRect) {
        hideWork?.cancel()

        let outgoing = toEnglish ? ModeLabel.chinese : ModeLabel.english
        let incoming = toEnglish ? ModeLabel.english : ModeLabel.chinese
        outgoingTag.configure(outgoing)
        incomingTag.configure(incoming)

        let pad: CGFloat = 4
        let width = tagSize.width + slide + pad * 2
        let height = tagSize.height + pad * 2
        var frame = NSRect(
            x: anchor.minX,
            y: anchor.minY - height - 6,
            width: width,
            height: height
        )
        if let screen = NSScreen.main?.visibleFrame {
            if frame.minY < screen.minY {
                frame.origin.y = anchor.maxY + 6
            }
            if frame.maxX > screen.maxX {
                frame.origin.x = max(screen.minX + 4, screen.maxX - frame.width - 4)
            }
            if frame.minX < screen.minX {
                frame.origin.x = screen.minX + 4
            }
        }
        panel.setFrame(frame, display: true)
        chrome.frame = NSRect(origin: .zero, size: frame.size)

        // Both tags share the resting center; outgoing starts there, incoming
        // starts just to the right (opacity 0) and slides into place.
        let rest = NSPoint(x: (width - tagSize.width) / 2, y: pad)
        outgoingTag.frame = NSRect(origin: rest, size: tagSize)
        outgoingTag.alphaValue = 1
        incomingTag.frame = NSRect(
            origin: NSPoint(x: rest.x + slide, y: pad),
            size: tagSize
        )
        incomingTag.alphaValue = 0

        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true

            outgoingTag.animator().alphaValue = 0
            outgoingTag.animator().frame = NSRect(
                origin: NSPoint(x: rest.x - slide, y: pad),
                size: tagSize
            )
            incomingTag.animator().alphaValue = 1
            incomingTag.animator().frame = NSRect(origin: rest, size: tagSize)
        }, completionHandler: { [weak self] in
            let work = DispatchWorkItem { [weak self] in
                self?.panel.orderOut(nil)
            }
            self?.hideWork = work
            // Brief hold so the incoming tag reads clearly before vanishing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: work)
        })
    }
}

private enum ModeLabel {
    case chinese
    case english

    var title: String {
        switch self {
        case .chinese: "中"
        case .english: "EN"
        }
    }

    var tint: NSColor {
        switch self {
        case .chinese: NSColor.systemRed.withAlphaComponent(0.92)
        case .english: NSColor.systemBlue.withAlphaComponent(0.92)
        }
    }
}

private final class TagView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.masksToBounds = true

        blur.material = .hudWindow
        blur.blendingMode = .withinWindow
        blur.state = .active
        blur.wantsLayer = true
        addSubview(blur)

        tint.wantsLayer = true
        tint.layer?.cornerRadius = 7
        addSubview(tint)

        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        label.sizeToFit()
        let size = label.fittingSize
        label.frame = NSRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2 - 0.5,
            width: size.width,
            height: size.height
        )
    }

    func configure(_ mode: ModeLabel) {
        label.stringValue = mode.title
        tint.layer?.backgroundColor = mode.tint.cgColor
        needsLayout = true
    }
}
