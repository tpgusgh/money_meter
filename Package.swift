// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TimeIsMoney",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "TimeIsMoney", path: "Sources/TimeIsMoney"),
        .testTarget(name: "TimeIsMoneyTests", dependencies: ["TimeIsMoney"], path: "Tests/TimeIsMoneyTests"),
    ]
)
