// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MeditationCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "MeditationCore", targets: ["MeditationCore"])],
    targets: [
        .target(name: "MeditationCore", path: "Core"),
        .testTarget(name: "MeditationCoreTests", dependencies: ["MeditationCore"], path: "Tests/CoreTests")
    ]
)
