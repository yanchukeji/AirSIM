// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LanU30Core",
    products: [
        .library(name: "LanU30Core", targets: ["LanU30Core"]),
    ],
    targets: [
        .target(name: "LanU30Core"),
        .testTarget(name: "LanU30CoreTests", dependencies: ["LanU30Core"]),
    ]
)
