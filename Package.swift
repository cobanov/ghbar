// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHBar",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "GHBar", path: "Sources/GHBar"),
        .testTarget(
            name: "GHBarTests",
            dependencies: ["GHBar"],
            path: "Tests/GHBarTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
