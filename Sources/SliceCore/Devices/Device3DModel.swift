//
//  Device3DModel.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import CoreGraphics
import Foundation

public enum Device3DModel: String, Codable, CaseIterable {
    case iPhone17ProMax = "iPhone 17 Pro Max"
    case iPhoneAir = "iPhone Air"
    case iPhone16ProMax = "iPhone 16 Pro Max"
    case iPhone16Plus = "iPhone 16 Plus"
    case iPhone15ProMax = "iPhone 15 Pro Max"
    case iPhone14ProMax = "iPhone 14 Pro Max"

    public var label: String { rawValue }

    /// The name without "iPhone", for tight spaces.
    public var shortLabel: String { String(rawValue.dropFirst("iPhone ".count)) }

    /// The bundled USDZ, in `Resources/Models`.
    var resource: String { rawValue }

    /// Who made the model (it's used under CC BY 4.0, which asks for credit), and where.
    public var credit: (author: String, url: URL) {
        switch self {
        case .iPhone17ProMax, .iPhone16ProMax: ("MajdyModels", URL(string: "https://sketchfab.com/MG990")!)
        case .iPhoneAir: ("Ranguel", URL(string: "https://sketchfab.com/Ranguel")!)
        case .iPhone16Plus: ("WhatIsLove", URL(string: "https://sketchfab.com/vladgutu11")!)
        case .iPhone15ProMax: ("PolygonMBW", URL(string: "https://sketchfab.com/PolygonMBW")!)
        case .iPhone14ProMax: ("akshatmittal", URL(string: "https://sketchfab.com/akshatmittal")!)
        }
    }

    /// The finishes it comes in; the first is the one it's modelled in.
    public var finishes: [Device3DFinish] {
        switch self {
        case .iPhone17ProMax: [.cosmicOrange, .deepBlue, .silver]
        case .iPhoneAir: [.skyBlue, .lightGold, .cloudWhite, .spaceBlack]
        case .iPhone16ProMax: [.desertTitanium, .blackTitanium, .whiteTitanium, .naturalTitanium]
        case .iPhone16Plus: [.teal, .ultramarine, .pink, .white, .black]
        case .iPhone15ProMax: [.naturalTitanium, .blueTitanium, .whiteTitanium, .blackTitanium]
        case .iPhone14ProMax: [.deepPurple, .spaceBlack, .silver, .gold]
        }
    }

    /// The display's node, for models whose names don't say which mesh is the screen.
    var displayNode: String? {
        switch self {
        case .iPhone17ProMax, .iPhone16ProMax, .iPhone15ProMax: nil
        case .iPhoneAir: nil
        case .iPhone16Plus: "Screen_BG"
        case .iPhone14ProMax: "YbXWdqEcjbfTKuN"
        }
    }

    /// The body colour it's modelled in, in linear light: parts of about this colour take a new finish.
    var bodyColor: SIMD3<Float> {
        switch self {
        case .iPhone17ProMax: SIMD3(0.815, 0.195, 0.060)
        case .iPhoneAir: SIMD3(0.736, 0.914, 1.0)
        case .iPhone16ProMax: SIMD3(0.486, 0.387, 0.325)
        case .iPhone16Plus: SIMD3(0.30, 0.58, 0.58)
        case .iPhone15ProMax: SIMD3(0.247, 0.247, 0.218)
        case .iPhone14ProMax: SIMD3(0.199, 0.148, 0.237)
        }
    }

    /// The body's materials by name, for models whose colours don't give their body parts away (greys, textures).
    var bodyMaterials: Set<String>? {
        switch self {
        case .iPhone17ProMax, .iPhone14ProMax: nil
        case .iPhoneAir: ["Metal_Body", "Frosted_Glass", "Frosted_Glass_Tint", "Plastic_Antena"]
        case .iPhone16ProMax: ["basecolor_001", "metalframe_002", "apple_logo_001"]
        case .iPhone16Plus: ["Back_Cover", "Rim_Buttons"]
        case .iPhone15ProMax: ["Natural_Titanium", "Edge", "Natural_Back_Glass", "Material"]
        }
    }
}

public enum Device3DFinish: String, Codable, CaseIterable {
    case cosmicOrange, deepBlue, silver, deepPurple, spaceBlack, gold
    case skyBlue, lightGold, cloudWhite
    case desertTitanium, blackTitanium, whiteTitanium, naturalTitanium, blueTitanium
    case ultramarine, teal, pink, white, black

    public var label: String {
        switch self {
        case .cosmicOrange: "Cosmic Orange"
        case .deepBlue: "Deep Blue"
        case .silver: "Silver"
        case .deepPurple: "Deep Purple"
        case .spaceBlack: "Space Black"
        case .gold: "Gold"
        case .skyBlue: "Sky Blue"
        case .lightGold: "Light Gold"
        case .cloudWhite: "Cloud White"
        case .desertTitanium: "Desert Titanium"
        case .blackTitanium: "Black Titanium"
        case .whiteTitanium: "White Titanium"
        case .naturalTitanium: "Natural Titanium"
        case .blueTitanium: "Blue Titanium"
        case .ultramarine: "Ultramarine"
        case .teal: "Teal"
        case .pink: "Pink"
        case .white: "White"
        case .black: "Black"
        }
    }

    /// The finish as it reads at a glance, for swatches.
    public var swatch: RGBA {
        switch self {
        case .cosmicOrange: RGBA(0.93, 0.52, 0.28)
        case .deepBlue: RGBA(0.24, 0.29, 0.39)
        case .silver: RGBA(0.86, 0.87, 0.87)
        case .deepPurple: RGBA(0.37, 0.33, 0.41)
        case .spaceBlack: RGBA(0.23, 0.23, 0.24)
        case .gold: RGBA(0.95, 0.89, 0.78)
        case .skyBlue: RGBA(0.75, 0.84, 0.91)
        case .lightGold: RGBA(0.92, 0.86, 0.73)
        case .cloudWhite: RGBA(0.95, 0.95, 0.93)
        case .desertTitanium: RGBA(0.77, 0.69, 0.62)
        case .blackTitanium: RGBA(0.24, 0.24, 0.25)
        case .whiteTitanium: RGBA(0.89, 0.88, 0.86)
        case .naturalTitanium: RGBA(0.71, 0.69, 0.65)
        case .blueTitanium: RGBA(0.28, 0.31, 0.37)
        case .ultramarine: RGBA(0.55, 0.62, 0.92)
        case .teal: RGBA(0.65, 0.80, 0.80)
        case .pink: RGBA(0.94, 0.75, 0.82)
        case .white: RGBA(0.96, 0.96, 0.95)
        case .black: RGBA(0.20, 0.21, 0.22)
        }
    }

    /// The body colour in linear light, at the brightness of the model's own body colour.
    var tint: SIMD3<Float> {
        switch self {
        case .cosmicOrange: SIMD3(0.815, 0.195, 0.060)
        case .deepBlue: SIMD3(0.045, 0.065, 0.13)
        case .silver: SIMD3(0.62, 0.63, 0.64)
        case .deepPurple: SIMD3(0.199, 0.148, 0.237)
        case .spaceBlack: SIMD3(0.035, 0.034, 0.038)
        case .gold: SIMD3(0.78, 0.60, 0.36)
        case .skyBlue: SIMD3(0.70, 0.79, 0.87)
        case .lightGold: SIMD3(0.84, 0.70, 0.48)
        case .cloudWhite: SIMD3(0.86, 0.86, 0.83)
        case .desertTitanium: SIMD3(0.486, 0.387, 0.325)
        case .blackTitanium: SIMD3(0.035, 0.035, 0.037)
        case .whiteTitanium: SIMD3(0.72, 0.71, 0.68)
        case .naturalTitanium: SIMD3(0.247, 0.247, 0.218)
        case .blueTitanium: SIMD3(0.06, 0.075, 0.11)
        case .ultramarine: SIMD3(0.10, 0.16, 0.62)
        case .teal: SIMD3(0.30, 0.58, 0.58)
        case .pink: SIMD3(0.85, 0.48, 0.60)
        case .white: SIMD3(0.88, 0.88, 0.86)
        case .black: SIMD3(0.03, 0.032, 0.035)
        }
    }
}
