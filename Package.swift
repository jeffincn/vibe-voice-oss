// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeVoiceOSS",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VibeVoiceOSS", targets: ["VibeVoiceOSS"])
    ],
    targets: [
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "VibeVoiceOSS",
            dependencies: ["ObjCExceptionCatcher"],
            path: "Sources/VibeVoiceOSS"
        ),
        .testTarget(
            name: "VibeVoiceOSSTests",
            dependencies: ["VibeVoiceOSS"]
        )
    ]
)
