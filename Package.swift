// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeVoiceOSS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VibeVoiceOSS", targets: ["VibeVoiceOSS"])
    ],
    targets: [
        .executableTarget(
            name: "VibeVoiceOSS",
            path: "Sources/VibeVoiceOSS"
        ),
        .testTarget(
            name: "VibeVoiceOSSTests",
            dependencies: ["VibeVoiceOSS"]
        )
    ]
)
