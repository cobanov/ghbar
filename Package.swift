// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GHBar",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/Defaults", from: "9.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "GHBar",
            dependencies: [.product(name: "Defaults", package: "Defaults")],
            path: "Sources/GHBar"
        ),
        .testTarget(
            name: "GHBarTests",
            dependencies: ["GHBar"],
            path: "Tests/GHBarTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
