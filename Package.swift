// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MacStat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacStat", targets: ["MacStat"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacStat",
            dependencies: [],
            path: "Sources/MacStat"
        )
    ]
)
