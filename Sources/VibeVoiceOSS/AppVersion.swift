import Foundation

enum AppVersion {
    /// Marketing version from Info.plist (`CFBundleShortVersionString`).
    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    /// Build number from Info.plist (`CFBundleVersion`).
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    /// Short label for menus, e.g. `v0.3.0`.
    static var shortLabel: String { "v\(marketing)" }

    /// Full label, e.g. `v0.3.0 (3)`.
    static var fullLabel: String { "v\(marketing) (\(build))" }
}
