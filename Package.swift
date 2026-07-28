// swift-tools-version: 6.2
import PackageDescription
import Foundation

let homebrewRimePrefix = "/opt/homebrew/opt/librime"
var rimeCSettings: [CSetting] = []
var rimeLinkerSettings: [LinkerSetting] = []
if FileManager.default.fileExists(atPath: "\(homebrewRimePrefix)/include/rime_api.h") {
    rimeCSettings.append(.unsafeFlags(["-I\(homebrewRimePrefix)/include"]))
    rimeLinkerSettings.append(.unsafeFlags(["-L\(homebrewRimePrefix)/lib", "-lrime"]))
}

let package = Package(
    name: "VibeVoiceOSS",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "VibeVoiceOSS", targets: ["VibeVoiceOSS"]),
        .executable(name: "VibeVoiceInputMethod", targets: ["VibeVoiceInputMethod"])
    ],
    dependencies: [
        // Vendored + patched: upstream pins mlx-swift `main`, which now requires Swift 6.3.
        // Local pin uses mlx-swift 0.31.4 (last release compatible with Swift 6.2.x).
        .package(path: "Vendor/mlx-swift-asr"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(name: "VibeVoiceInputShared", path: "Sources/VibeVoiceInputShared"),
        .target(
            name: "VibeVoiceRime",
            path: "Sources/VibeVoiceRime",
            publicHeadersPath: "include",
            cSettings: rimeCSettings,
            linkerSettings: rimeLinkerSettings
        ),
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "VibeVoiceOSS",
            dependencies: [
                "VibeVoiceInputShared",
                "ObjCExceptionCatcher",
                .product(name: "ArgmaxOSS", package: "argmax-oss-swift"),
                .product(name: "MLXASR", package: "mlx-swift-asr"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/VibeVoiceOSS"
        ),
        .executableTarget(
            name: "VibeVoiceInputMethod",
            dependencies: ["VibeVoiceInputShared", "VibeVoiceRime"],
            path: "Sources/VibeVoiceInputMethod",
            exclude: ["InputMethodInfo.plist", "en.lproj", "zh-Hans.lproj"]
        ),
        .testTarget(
            name: "VibeVoiceOSSTests",
            dependencies: ["VibeVoiceOSS", "VibeVoiceInputShared", "VibeVoiceRime"]
        )
    ]
)
