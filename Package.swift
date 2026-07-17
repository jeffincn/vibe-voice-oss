// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeVoice",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VibeVoice", targets: ["VibeVoice"])
    ],
    targets: [
        .executableTarget(
            name: "VibeVoice",
            path: "Sources/VibeVoice"
        ),
        .testTarget(
            name: "VibeVoiceTests",
            dependencies: ["VibeVoice"]
        )
    ]
)
