// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GCloudMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GCloudMenuBar", targets: ["GCloudMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "GCloudMenuBar",
            path: "Sources/GCloudMenuBar"
        )
    ]
)
