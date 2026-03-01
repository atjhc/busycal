// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "BusyCal",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BusyCal",
            path: "Sources/BusyCal"
        )
    ]
)
