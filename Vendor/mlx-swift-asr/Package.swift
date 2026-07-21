// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "mlx-swift-asr",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .library(name: "MLXASR", targets: ["MLXASR"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"),
        // Last commit before maskFill / greatestFiniteMagnitudeArray (needs mlx-swift ≥ 0.31.5).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", revision: "d2424294a6c3bbd0de37a0761d80efc05e6813dd"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.1.6"),
    ],
    targets: [
        .target(
            name: "MLXASR",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXFast", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .testTarget(
            name: "MLXASRTests",
            dependencies: ["MLXASR"],
            resources: [
                .copy("Resources"),
            ]
        ),
    ]
)
