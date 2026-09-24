// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NowCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "NowCore", targets: ["NowCore"]),
    ],
    targets: [
        .target(name: "NowCore"),
        .testTarget(name: "NowCoreTests", dependencies: ["NowCore"]),
    ]
)
