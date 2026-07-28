import AppKit

/// Non-activating help panel opened from the input-source menu (Squirrel-style).
@MainActor
final class InputMethodHelpPanel {
    static let shared = InputMethodHelpPanel()

    private let panel: NSPanel
    private let scroll = NSScrollView()
    private let textView = NSTextView()

    private init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 480),
            styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = Self.localizedTitle
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.minSize = NSSize(width: 360, height: 320)

        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 14)
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        scroll.documentView = textView

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = root
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
    }

    func show() {
        textView.string = Self.helpBody
        textView.scrollToBeginningOfDocument(nil)
        panel.title = Self.localizedTitle
        if !panel.isVisible {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static var prefersChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    private static var localizedTitle: String {
        prefersChinese ? "Vibe Type 快捷键说明" : "Vibe Type Shortcuts"
    }

    private static var helpBody: String {
        if prefersChinese {
            return """
            候选栏
            · 空格 — 上屏当前高亮候选
            · 数字 1–9 — 直接选择对应候选
            · Tab / Shift+Tab — 前后切换高亮（部分 App 如 Cursor 可能截获 Tab，可用左右方向键）
            · ← / → — 移动高亮
            · ↑ / ↓ — 翻页

            输入与模式
            · 左 Shift 轻点 — 中 / 英切换（出现 中↔EN 提示）
            · Esc — 清空当前编码
            · Return — 确认 / 上屏
            · 退格 — 删除编码

            中英混输
            · 拼音中间可直接嵌英文词，例如：
              woxiwangkeyiyongtablaiqiehuan → 我希望可以用 tab 来切换
              woxiangyongcoreml… → 我想用 Core ML …
            · 支持键盘键名与常见开发词（Tab、Shift、Enter、Swift、Docker 等）
            · 候选左侧带图标的条目为智能组句 / 纠错结果

            语音输入
            · 菜单栏选择「语音输入」，或使用主应用 Vibe Voice OSS 的录音快捷键

            更多
            ·「打开主应用…」可启动 Vibe Voice OSS 进行 ASR / 模型等设置
            ·「日志…」打开混输调试日志目录
            ·「使用说明（GitHub）…」查看项目文档
            """
        }
        return """
        Candidates
        · Space — commit highlighted candidate
        · Digits 1–9 — commit that candidate
        · Tab / Shift+Tab — move highlight (some apps like Cursor may steal Tab; use ← → instead)
        · ← / → — move highlight
        · ↑ / ↓ — previous / next page

        Typing & mode
        · Tap left Shift — Chinese / English toggle (中↔EN HUD)
        · Esc — clear composition
        · Return — confirm / commit
        · Delete — backspace code

        Mixed Chinese + English
        · Embed English inside pinyin, e.g.:
          woxiwangkeyiyongtablaiqiehuan → 我希望可以用 tab 来切换
          woxiangyongcoreml… → 我想用 Core ML …
        · Keyboard / coding terms (Tab, Shift, Enter, Swift, Docker, …) are recognized
        · Rows with an icon are smart phrase / typo-fix results

        Voice
        · Use “Voice Input” in this menu, or the hotkey in Vibe Voice OSS

        More
        · “Open Main App…” launches Vibe Voice OSS for ASR / model settings
        · “Logs…” opens the mixed-input debug log folder
        · “Documentation (GitHub)…” opens the project README
        """
    }
}
