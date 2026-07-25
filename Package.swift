// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VibeVoiceOSS",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "VibeVoiceOSS", targets: ["VibeVoiceOSS"])
    ],
    dependencies: [
        // Vendored + patched: upstream pins mlx-swift `main`, which now requires Swift 6.3.
        // Local pin uses mlx-swift 0.31.4 (last release compatible with Swift 6.2.x).
        .package(path: "Vendor/mlx-swift-asr"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "ObjCExceptionCatcher",
            path: "Sources/ObjCExceptionCatcher",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "VibeVoiceOSS",
            dependencies: [
                "ObjCExceptionCatcher",
                .product(name: "MLXASR", package: "mlx-swift-asr"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/VibeVoiceOSS"
        ),
        .testTarget(
            name: "VibeVoiceOSSTests",
            dependencies: ["VibeVoiceOSS"]
        )
    ]
)
