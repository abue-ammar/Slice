// swift-tools-version: 5.9
// Vendored from github.com/raymondjavaxx/SmoothGradient (MIT), minus its snapshot tests.
import PackageDescription

let package = Package(
    name: "SmoothGradient",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SmoothGradient", targets: ["SmoothGradient"])
    ],
    targets: [
        .target(name: "SmoothGradient")
    ]
)
