// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Scouter",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(
            name: "Scouter",
            targets: ["Scouter"]),
    ],
    dependencies: [
        .package(url: "https://github.com/1amageek/Unknown.git", branch: "main"),
        .package(url: "https://github.com/1amageek/AspectAnalyzer.git", branch: "main"),
        .package(url: "https://github.com/1amageek/Remark.git", branch: "main"),
        .package(url: "https://github.com/1amageek/OllamaKit.git", branch: "main"),
        .package(url: "https://github.com/1amageek/SwiftRetry.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-log.git", branch: "main"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", branch: "master"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", branch: "main"),
        .package(url: "https://github.com/MacPaw/OpenAI.git", branch: "main"),
    ],
    targets: [
        .target(
            name: "Scouter",
            dependencies: [
                "Unknown",
                "AspectAnalyzer",
                "Remark",
                "OllamaKit",
                "SwiftRetry",
                "SwiftSoup",
                "OpenAI",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .executableTarget(
            name: "ScouterCLI",
            dependencies: [
                "Scouter",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "ScouterTests",
            dependencies: ["Scouter"]
        ),
    ]
)
