import AppKit

/// Visual mark for synthesised candidates (icons only — never text like "推理").
enum CandidateBadge: Equatable {
    /// Full-line mixed / contextual reasoning.
    case reasoning
    /// Adjacent-key transpose recovery (e.g. chnag → chang).
    case typoFix
    /// Flat/retroflex is never mixed; optional n/l / nasal rescue only.
    case fuzzyAccent

    func image(pointSize: CGFloat, tint: NSColor) -> NSImage {
        switch self {
        case .reasoning:
            return CandidateIconFactory.wand(pointSize: pointSize, tint: tint)
        case .typoFix:
            return CandidateIconFactory.swapLetters(pointSize: pointSize, tint: tint)
        case .fuzzyAccent:
            return CandidateIconFactory.accentWave(pointSize: pointSize, tint: tint)
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .reasoning: "推理候选"
        case .typoFix: "拼音纠错（邻位颠倒）"
        case .fuzzyAccent: "模糊音容错（n/l、前后鼻音；不含平翘舌）"
        }
    }
}

enum CandidateStatusKind: Equatable {
    case coreML
    case rime
    case learning
    case loading

    var emoji: String {
        switch self {
        case .coreML: "🧠"
        case .rime: "文"
        case .learning: "📚"
        case .loading: "…"
        }
    }

    func image(pointSize: CGFloat, tint: NSColor) -> NSImage? {
        switch self {
        case .coreML:
            return CandidateIconFactory.brain(pointSize: pointSize, tint: tint)
        case .rime:
            return nil // emoji 「文」 reads clearer than a generic glyph
        case .learning:
            return CandidateIconFactory.book(pointSize: pointSize, tint: tint)
        case .loading:
            return nil
        }
    }
}

/// Vector icons drawn with Bezier paths so the IMK agent does not depend on
/// SF Symbol catalogs (which often render as tofu / mojibake in input methods).
enum CandidateIconFactory {
    static func wand(pointSize: CGFloat, tint: NSColor) -> NSImage {
        draw(pointSize: pointSize) { ctx, side in
            let stroke = max(1.2, side * 0.08)
            ctx.setStrokeColor(tint.cgColor)
            ctx.setFillColor(tint.cgColor)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Wand shaft.
            ctx.beginPath()
            ctx.move(to: CGPoint(x: side * 0.22, y: side * 0.78))
            ctx.addLine(to: CGPoint(x: side * 0.62, y: side * 0.30))
            ctx.strokePath()

            // Wand tip diamond.
            let tip = CGPoint(x: side * 0.70, y: side * 0.22)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: tip.x, y: tip.y - side * 0.10))
            ctx.addLine(to: CGPoint(x: tip.x + side * 0.09, y: tip.y))
            ctx.addLine(to: CGPoint(x: tip.x, y: tip.y + side * 0.10))
            ctx.addLine(to: CGPoint(x: tip.x - side * 0.09, y: tip.y))
            ctx.closePath()
            ctx.fillPath()

            // Sparkles.
            drawSparkle(ctx, center: CGPoint(x: side * 0.82, y: side * 0.18), radius: side * 0.07)
            drawSparkle(ctx, center: CGPoint(x: side * 0.88, y: side * 0.38), radius: side * 0.05)
            drawSparkle(ctx, center: CGPoint(x: side * 0.58, y: side * 0.12), radius: side * 0.045)
        }
    }

    static func circularArrows(pointSize: CGFloat, tint: NSColor) -> NSImage {
        draw(pointSize: pointSize) { ctx, side in
            let stroke = max(1.2, side * 0.09)
            ctx.setStrokeColor(tint.cgColor)
            ctx.setFillColor(tint.cgColor)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)

            let rect = CGRect(
                x: side * 0.18,
                y: side * 0.18,
                width: side * 0.64,
                height: side * 0.64
            )
            ctx.beginPath()
            ctx.addArc(
                center: CGPoint(x: rect.midX, y: rect.midY),
                radius: rect.width * 0.42,
                startAngle: .pi * 0.15,
                endAngle: .pi * 1.55,
                clockwise: false
            )
            ctx.strokePath()

            // Arrow head.
            let tip = CGPoint(x: side * 0.72, y: side * 0.28)
            ctx.beginPath()
            ctx.move(to: tip)
            ctx.addLine(to: CGPoint(x: tip.x - side * 0.12, y: tip.y + side * 0.02))
            ctx.addLine(to: CGPoint(x: tip.x - side * 0.02, y: tip.y + side * 0.12))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    /// Two letters with a swap arrow — adjacent-key transpose correction.
    static func swapLetters(pointSize: CGFloat, tint: NSColor) -> NSImage {
        draw(pointSize: pointSize) { ctx, side in
            let stroke = max(1.1, side * 0.08)
            ctx.setStrokeColor(tint.cgColor)
            ctx.setFillColor(tint.cgColor)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            // Left block
            ctx.stroke(CGRect(x: side * 0.12, y: side * 0.28, width: side * 0.28, height: side * 0.44))
            // Right block
            ctx.stroke(CGRect(x: side * 0.60, y: side * 0.28, width: side * 0.28, height: side * 0.44))
            // Swap arrows
            ctx.beginPath()
            ctx.move(to: CGPoint(x: side * 0.42, y: side * 0.40))
            ctx.addLine(to: CGPoint(x: side * 0.58, y: side * 0.40))
            ctx.move(to: CGPoint(x: side * 0.58, y: side * 0.60))
            ctx.addLine(to: CGPoint(x: side * 0.42, y: side * 0.60))
            ctx.strokePath()
            // Arrow heads
            ctx.beginPath()
            ctx.move(to: CGPoint(x: side * 0.58, y: side * 0.40))
            ctx.addLine(to: CGPoint(x: side * 0.52, y: side * 0.34))
            ctx.addLine(to: CGPoint(x: side * 0.52, y: side * 0.46))
            ctx.closePath()
            ctx.fillPath()
            ctx.beginPath()
            ctx.move(to: CGPoint(x: side * 0.42, y: side * 0.60))
            ctx.addLine(to: CGPoint(x: side * 0.48, y: side * 0.54))
            ctx.addLine(to: CGPoint(x: side * 0.48, y: side * 0.66))
            ctx.closePath()
            ctx.fillPath()
        }
    }

    /// Wave / accent mark — fuzzy initial/final tolerance.
    static func accentWave(pointSize: CGFloat, tint: NSColor) -> NSImage {
        draw(pointSize: pointSize) { ctx, side in
            let stroke = max(1.2, side * 0.09)
            ctx.setStrokeColor(tint.cgColor)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: side * 0.12, y: side * 0.55))
            ctx.addCurve(
                to: CGPoint(x: side * 0.50, y: side * 0.55),
                control1: CGPoint(x: side * 0.24, y: side * 0.22),
                control2: CGPoint(x: side * 0.38, y: side * 0.88)
            )
            ctx.addCurve(
                to: CGPoint(x: side * 0.88, y: side * 0.55),
                control1: CGPoint(x: side * 0.62, y: side * 0.22),
                control2: CGPoint(x: side * 0.76, y: side * 0.88)
            )
            ctx.strokePath()
            // Small spark at peak
            drawSparkle(ctx, center: CGPoint(x: side * 0.50, y: side * 0.28), radius: side * 0.06)
        }
    }

    static func brain(pointSize: CGFloat, tint: NSColor) -> NSImage {
        draw(pointSize: pointSize) { ctx, side in
            let stroke = max(1.1, side * 0.08)
            ctx.setStrokeColor(tint.cgColor)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)

            let box = CGRect(x: side * 0.18, y: side * 0.22, width: side * 0.64, height: side * 0.56)
            let path = CGMutablePath()
            path.addRoundedRect(in: box, cornerWidth: side * 0.16, cornerHeight: side * 0.16)
            ctx.addPath(path)
            ctx.strokePath()

            ctx.beginPath()
            ctx.move(to: CGPoint(x: box.midX, y: box.minY + side * 0.08))
            ctx.addLine(to: CGPoint(x: box.midX, y: box.maxY - side * 0.08))
            ctx.strokePath()

            ctx.beginPath()
            ctx.move(to: CGPoint(x: box.minX + side * 0.10, y: box.midY))
            ctx.addLine(to: CGPoint(x: box.maxX - side * 0.10, y: box.midY))
            ctx.strokePath()
        }
    }

    static func book(pointSize: CGFloat, tint: NSColor) -> NSImage {
        draw(pointSize: pointSize) { ctx, side in
            let stroke = max(1.1, side * 0.08)
            ctx.setStrokeColor(tint.cgColor)
            ctx.setLineWidth(stroke)
            ctx.setLineJoin(.round)

            let page = CGRect(x: side * 0.22, y: side * 0.18, width: side * 0.56, height: side * 0.64)
            ctx.stroke(page)
            ctx.beginPath()
            ctx.move(to: CGPoint(x: page.midX, y: page.minY))
            ctx.addLine(to: CGPoint(x: page.midX, y: page.maxY))
            ctx.strokePath()
        }
    }

    private static func drawSparkle(_ ctx: CGContext, center: CGPoint, radius: CGFloat) {
        ctx.beginPath()
        ctx.move(to: CGPoint(x: center.x, y: center.y - radius))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y + radius))
        ctx.move(to: CGPoint(x: center.x - radius, y: center.y))
        ctx.addLine(to: CGPoint(x: center.x + radius, y: center.y))
        ctx.strokePath()
    }

    private static func draw(
        pointSize: CGFloat,
        _ body: (CGContext, CGFloat) -> Void
    ) -> NSImage {
        let side = max(12, ceil(pointSize + 2))
        let image = NSImage(size: NSSize(width: side, height: side))
        image.lockFocus()
        if let ctx = NSGraphicsContext.current?.cgContext {
            // AppKit is flipped relative to the paths above.
            ctx.translateBy(x: 0, y: side)
            ctx.scaleBy(x: 1, y: -1)
            body(ctx, side)
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}

/// Floating candidate strip that never becomes key. `IMKCandidates` steals
/// digit and arrow keydowns while it is visible, which is why 1–9 / ←→ were
/// dead even though Escape and Delete (routed to the controller) still worked.
/// Owning the window ourselves keeps every keystroke in `handle(_:client:)`.
@MainActor
final class CandidateBarWindow {
    static let shared = CandidateBarWindow()

    private let panel: NSPanel
    private let shell = NSView(frame: .zero)
    private let stack = NSStackView()
    private let cornerRadius: CGFloat = 8

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        // Match Squirrel: Cursor / Electron floating composer panels sit above
        // `.floating`, so a normal palette level gets painted over and only the
        // rightmost candidates peek out. Shielding level keeps the strip on top.
        panel.level = NSWindow.Level(Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Window shadow follows the rectangular frame and shows as a hard black
        // outline around the rounded strip. Soft depth comes from the layer below.
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true

        shell.wantsLayer = true
        shell.layer?.masksToBounds = false
        shell.layer?.shadowColor = NSColor.black.cgColor
        shell.layer?.shadowOpacity = 0.28
        shell.layer?.shadowRadius = 10
        shell.layer?.shadowOffset = CGSize(width: 0, height: -2)

        let chrome = NSVisualEffectView(frame: .zero)
        chrome.material = .menu
        chrome.blendingMode = .behindWindow
        chrome.state = .active
        chrome.wantsLayer = true
        chrome.layer?.cornerRadius = cornerRadius
        chrome.layer?.masksToBounds = true
        chrome.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .horizontal
        stack.spacing = 2
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        chrome.addSubview(stack)
        shell.addSubview(chrome)
        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: shell.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: shell.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: shell.topAnchor),
            chrome.bottomAnchor.constraint(equalTo: shell.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: chrome.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: chrome.trailingAnchor),
            stack.topAnchor.constraint(equalTo: chrome.topAnchor),
            stack.bottomAnchor.constraint(equalTo: chrome.bottomAnchor),
        ])
        panel.contentView = shell
    }

    private func updateRoundedShadow(for size: NSSize) {
        let path = CGPath(
            roundedRect: CGRect(origin: .zero, size: size),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        shell.layer?.shadowPath = path
    }

    func hide() {
        panel.orderOut(nil)
    }

    func show(
        candidates: [String],
        highlight: Int,
        anchor: NSRect,
        badges: [CandidateBadge?] = [],
        status: CandidateStatusKind? = nil,
        hasPreviousPage: Bool = false,
        hasNextPage: Bool = false
    ) {
        rebuild(
            candidates: candidates,
            highlight: highlight,
            badges: badges,
            status: status,
            hasPreviousPage: hasPreviousPage,
            hasNextPage: hasNextPage
        )
        panel.layoutIfNeeded()
        let size = stack.fittingSize
        let width = max(size.width + 4, 80)
        let height = max(size.height + 2, 32)

        var frame = NSRect(
            x: anchor.minX,
            y: anchor.minY - height - 4,
            width: width,
            height: height
        )
        if let screen = NSScreen.main?.visibleFrame {
            if frame.minY < screen.minY {
                frame.origin.y = anchor.maxY + 4
            }
            if frame.maxX > screen.maxX {
                frame.origin.x = max(screen.minX + 4, screen.maxX - frame.width - 4)
            }
            if frame.minX < screen.minX {
                frame.origin.x = screen.minX + 4
            }
        }
        panel.setFrame(frame, display: true)
        updateRoundedShadow(for: frame.size)
        panel.orderFrontRegardless()
    }

    private func rebuild(
        candidates: [String],
        highlight: Int,
        badges: [CandidateBadge?] = [],
        status: CandidateStatusKind? = nil,
        hasPreviousPage: Bool = false,
        hasNextPage: Bool = false
    ) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Cap hard at 9 so number keys always map 1…n.
        let visible = Array(candidates.prefix(9))
        for (index, text) in visible.enumerated() {
            let highlighted = index == highlight
            let container = NSView()
            container.wantsLayer = true
            container.layer?.cornerRadius = 4
            if highlighted {
                container.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
            }

            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 5
            row.alignment = .centerY
            row.translatesAutoresizingMaskIntoConstraints = false

            let accent: NSColor = highlighted ? .white : .controlAccentColor
            let body: NSColor = highlighted ? .white : .labelColor

            // Number chip — always 1…9 on the current page.
            let indexLabel = NSTextField(labelWithString: "\(index + 1)")
            indexLabel.font = .systemFont(ofSize: 13, weight: .bold)
            indexLabel.textColor = accent
            indexLabel.setContentHuggingPriority(.required, for: .horizontal)

            let textLabel = NSTextField(labelWithString: text)
            textLabel.font = .systemFont(ofSize: 14)
            textLabel.textColor = body

            row.addArrangedSubview(indexLabel)
            row.addArrangedSubview(textLabel)

            if let badge = index < badges.count ? badges[index] : nil {
                let icon = iconView(badge.image(pointSize: 13, tint: accent))
                icon.toolTip = badge.accessibilityLabel
                row.addArrangedSubview(icon)
            }

            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(row)
            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 6),
                row.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -6),
                row.topAnchor.constraint(equalTo: container.topAnchor, constant: 3),
                row.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -3),
            ])
            stack.addArrangedSubview(container)

            if index < visible.count - 1 {
                let divider = NSBox()
                divider.boxType = .separator
                divider.translatesAutoresizingMaskIntoConstraints = false
                divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
                stack.addArrangedSubview(divider)
            }
        }

        if hasPreviousPage || hasNextPage || status != nil {
            let divider = NSBox()
            divider.boxType = .separator
            divider.translatesAutoresizingMaskIntoConstraints = false
            divider.widthAnchor.constraint(equalToConstant: 1).isActive = true
            stack.addArrangedSubview(divider)

            let wrap = NSStackView()
            wrap.orientation = .horizontal
            wrap.spacing = 4
            wrap.alignment = .centerY
            wrap.edgeInsets = NSEdgeInsets(top: 2, left: 4, bottom: 2, right: 6)

            let tint = NSColor.secondaryLabelColor
            if hasPreviousPage {
                wrap.addArrangedSubview(pageChevron(symbol: "⌃", tint: tint, tip: "上一页（↑）"))
            }
            if let status {
                if let image = status.image(pointSize: 11, tint: tint) {
                    wrap.addArrangedSubview(iconView(image))
                } else {
                    let emoji = NSTextField(labelWithString: status.emoji)
                    emoji.font = .systemFont(ofSize: 11)
                    emoji.textColor = tint
                    wrap.addArrangedSubview(emoji)
                }
            }
            if hasNextPage {
                wrap.addArrangedSubview(pageChevron(symbol: "⌄", tint: tint, tip: "下一页（↓）"))
            }
            stack.addArrangedSubview(wrap)
        }
    }

    private func pageChevron(symbol: String, tint: NSColor, tip: String) -> NSTextField {
        let label = NSTextField(labelWithString: symbol)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = tint
        label.toolTip = tip
        label.setContentHuggingPriority(.required, for: .horizontal)
        return label
    }

    private func iconView(_ image: NSImage) -> NSImageView {
        let view = NSImageView()
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        view.translatesAutoresizingMaskIntoConstraints = false
        view.setContentHuggingPriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            view.widthAnchor.constraint(equalToConstant: image.size.width),
            view.heightAnchor.constraint(equalToConstant: image.size.height),
        ])
        return view
    }
}
