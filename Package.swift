// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VibeVoiceOSS",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "VibeVoiceOSS", targets: ["VibeVoiceOSS"])
    ],
    dependencies: [
        .package(url: "https://github.com/ontypehq/mlx-swift-asr.git", branch: "main"),
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
                .product(name: "ArgmaxOSS", package: "argmax-oss-swift"),
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
