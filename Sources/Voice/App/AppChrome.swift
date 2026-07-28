import SwiftUI

/// Shared visual tokens for Settings and MenuBar panels.
enum AppChrome {
    static let canvas = Color(red: 0.953, green: 0.953, blue: 0.957)
    static let panel = Color.white
    static let sidebarIdle = Color(red: 0.55, green: 0.55, blue: 0.58)
    static let sidebarActiveFill = Color(red: 0.918, green: 0.918, blue: 0.925)
    static let ink = Color.black
    static let hairline = Color(red: 0.89, green: 0.89, blue: 0.90)
    static let muted = Color(red: 0.45, green: 0.45, blue: 0.48)

    static let success = Color(red: 0.15, green: 0.55, blue: 0.28)
    static let danger = Color(red: 0.75, green: 0.2, blue: 0.2)

    static func connectionColor(for text: String) -> Color {
        let ok = text.contains("成功") || text.contains("可用") || text.contains("正常")
        let bad = text.contains("失败") || text.contains("不在服务列表")
        if bad { return danger }
        if ok { return success }
        return muted
    }
}

extension View {
    /// White card on the light canvas — used by Settings detail and MenuBar sections.
    func appChromeCard(padding: CGFloat = 12, cornerRadius: CGFloat = 12) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(AppChrome.panel)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppChrome.hairline, lineWidth: 1)
            )
    }
}
