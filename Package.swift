// swift-tools-version: 6.2
import PackageDescription
import Foundation

/// Monorepo layout:
/// - Sources/Voice            → menu-bar voice dictation app (VibeVoiceOSS)
/// - Sources/InputMethod      → IMK pinyin input method (VibeVoiceInputMethod)
/// - Sources/Shared           → cross-product bridge (voice ↔ IMK)
/// - Sources/Pinyin           → pinyin engine, lexicon, candidate ranking
/// - Sources/Rime             → librime C adapter
/// - Sources/ObjCExceptionCatcher
///
/// Resources:
/// - Resources/Voice          → app Info.plist, entitlements, icon
/// - Resources/InputMethod    → RimeData, Lexicon, CandidateRanker, VibeType assets

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
        // Cross-product: voice ↔ IMK request bridge (file + Darwin notification).
        .target(
            name: "VibeVoiceShared",
            path: "Sources/Shared"
        ),
        // Pinyin engine shared by the IMK server (and Voice settings that tune it).
        .target(
            name: "VibeVoicePinyin",
            dependencies: ["VibeVoiceShared"],
            path: "Sources/Pinyin"
        ),
        .target(
            name: "VibeVoiceRime",
            path: "Sources/Rime",
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
                "VibeVoiceShared",
                "VibeVoicePinyin",
                "ObjCExceptionCatcher",
                .product(name: "ArgmaxOSS", package: "argmax-oss-swift"),
                .product(name: "MLXASR", package: "mlx-swift-asr"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/Voice"
        ),
        .executableTarget(
            name: "VibeVoiceInputMethod",
            dependencies: ["VibeVoiceShared", "VibeVoicePinyin", "VibeVoiceRime"],
            path: "Sources/InputMethod",
            exclude: ["InputMethodInfo.plist", "en.lproj", "zh-Hans.lproj"]
        ),
        .testTarget(
            name: "VoiceTests",
            dependencies: ["VibeVoiceOSS"]
        ),
        .testTarget(
            name: "PinyinTests",
            dependencies: ["VibeVoicePinyin", "VibeVoiceRime"]
        ),
        .testTarget(
            name: "SharedTests",
            dependencies: ["VibeVoiceShared"]
        ),
    ]
)
