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
        .package(url: "https://github.com/1amageek/Selenops.git", branch: "main"),
        .package(url: "https://github.com/1amageek/AspectAnalyzer.git", branch: "main"),
        .package(url: "https://github.com/1amageek/Remark.git", branch: "main"),
        .package(url: "https://github.com/1amageek/OllamaKit.git", branch: "main"),
        .package(url: "https://github.com/1amageek/SwiftRetry.git", branch: "main"),
        .package(url: "https://github.com/apple/swift-log.git", branch: "main"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", branch: "master")                
    ],
    targets: [
        .target(
            name: "Scouter",
            dependencies: [
                "Unknown",
                "Selenops",
                "AspectAnalyzer",
                "Remark",
                "OllamaKit",
                "SwiftRetry",
                "SwiftSoup",
                .product(name: "Logging", package: "swift-log")
            ]
        ),
        .testTarget(
            name: "ScouterTests",
            dependencies: ["Scouter"]
        ),
    ]
)
