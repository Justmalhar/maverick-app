// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaverickProtocol",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [
        .library(name: "MaverickProtocol", targets: ["MaverickProtocol"])
    ],
    targets: [
        .target(name: "MaverickProtocol"),
        .testTarget(name: "MaverickProtocolTests", dependencies: ["MaverickProtocol"])
    ]
)
