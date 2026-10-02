// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VoltIQCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "VoltIQ", targets: ["VoltIQ"])],
    targets: [
        .target(name: "VoltIQ", path: "VoltIQ/Core"),
        .testTarget(name: "VoltIQTests", dependencies: ["VoltIQ"], path: "VoltIQTests")
    ]
)
