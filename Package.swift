// swift-tools-version: 6.2
//
//  Package.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/6/26.
//

import PackageDescription

let package = Package(
    name: "SliceCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "SliceCore", targets: ["SliceCore"]),
    ],
    dependencies: [
        // Parakeet speech recognition on Core ML. Plain ASR doesn't need the NeMo text-normalisation engine, so its trait is off.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7", traits: []),
    ],
    targets: [
        .target(name: "SliceCore", dependencies: [.product(name: "FluidAudio", package: "FluidAudio")], resources: [.copy("Resources/Shaders/ClickRipple.metal.txt"), .copy("Resources/Shaders/ClickSpotlight.metal.txt"), .copy("Resources/Shaders/LiquidGlass.metal.txt"), .copy("Resources/Shaders/DeviceFrame.metal.txt"), .copy("Resources/Shaders/ZoomBlur.metal.txt"), .copy("Resources/Shaders/CursorTrail.metal.txt"), .copy("Resources/Shaders/CameraBlur.metal.txt"), .copy("Resources/Shaders/ScreenTilt.metal.txt"), .copy("Resources/Shaders/Transitions.metal.txt"), .copy("Resources/Cursors"), .copy("Resources/Sounds"), .copy("Resources/Models")]),
        .testTarget(name: "SliceCoreTests", dependencies: ["SliceCore"]),
    ],
    swiftLanguageModes: [.v5]
)
