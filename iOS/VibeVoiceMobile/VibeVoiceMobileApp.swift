import SwiftUI

@main
struct VibeVoiceMobileApp: App {
    init() {
        // First line of every session, so a pulled log always starts by saying
        // which build produced it and whether the shared container was there.
        MobileLog.info(.lifecycle, "app.launched", [
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "storage": DiagnosticStore.shared.storageDescription,
            "system": ProcessInfo.processInfo.operatingSystemVersionString,
        ])
    }

    var body: some Scene {
        WindowGroup {
            MobileHomeView()
        }
    }
}
