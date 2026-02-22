// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "AppStoreReviewPrompt",
    platforms: [
        .iOS(.v17), .macOS(.v14)
    ],
    products: [
        .library(
            name: "AppStoreReviewPrompt",
            targets: ["AppStoreReviewPrompt"]),
    ],
    targets: [
        .target(
            name: "AppStoreReviewPrompt",
            dependencies: []),
        .testTarget(
            name: "AppStoreReviewPromptTests",
            dependencies: ["AppStoreReviewPrompt"]),
    ]
)
