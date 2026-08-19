// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "awasero-music",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AwaseroMusic", targets: ["AwaseroMusic"])
    ],
    targets: [
        .executableTarget(
            name: "AwaseroMusic",
            path: "Sources/AwaseroMusic"
        ),
        .testTarget(
            name: "AwaseroMusicTests",
            dependencies: ["AwaseroMusic"],
            path: "Tests/AwaseroMusicTests"
        )
    ]
)
