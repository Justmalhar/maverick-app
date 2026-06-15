// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MaverickNoise",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "MaverickNoise", targets: ["MaverickNoise"])],
    targets: [
        .target(name: "MaverickNoise"),
        .testTarget(name: "MaverickNoiseTests", dependencies: ["MaverickNoise"]),
    ]
)
