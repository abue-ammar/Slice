//
//  Cursor.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/9/26.
//

import CoreGraphics
import CoreImage
import Foundation
import ImageIO

public struct CursorSettings: Codable, Equatable {
    public var visible = true
    public var size = 2.5
    public var style: CursorStyle = .native
    public var smoothing = 0.5
    public var motionBlur = 0.8
    public var tilt = 0.0
    public var tiltMaxAngle = 14.0
    public var tiltSmoothing = 0.15
    public var stateDelay = 0.12
    public var clickEffect: ClickEffect = .none
    public var clickEffectSize = 1.0
    public var clickSound: ClickSound = .none
    public var clickSoundVolume = 0.5
    public var clickPress = false
    public var clickPressScale = 0.8
    public var clickPressDuration = 0.3
    public var loopPosition = false
    public var hideWhenIdle = false
    public var idleDelay = 2.0

    public static let idleDelayPresets: [Double] = [0.5, 1, 2, 5]
    static let idleFade = 0.3

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CursorSettings()
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? d.visible
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        style = (try? c.decodeIfPresent(CursorStyle.self, forKey: .style)) ?? d.style
        if let s = try c.decodeIfPresent(Double.self, forKey: .smoothing) {
            smoothing = s
        } else if let on = try c.decodeIfPresent(Bool.self, forKey: .legacySmooth) {
            smoothing = on ? d.smoothing : 0
        }
        motionBlur = try c.decodeIfPresent(Double.self, forKey: .motionBlur) ?? d.motionBlur
        tilt = try c.decodeIfPresent(Double.self, forKey: .tilt) ?? d.tilt
        tiltMaxAngle = try c.decodeIfPresent(Double.self, forKey: .tiltMaxAngle) ?? d.tiltMaxAngle
        tiltSmoothing = try c.decodeIfPresent(Double.self, forKey: .tiltSmoothing) ?? d.tiltSmoothing
        stateDelay = try c.decodeIfPresent(Double.self, forKey: .stateDelay) ?? d.stateDelay
        clickEffect = (try? c.decodeIfPresent(ClickEffect.self, forKey: .clickEffect)) ?? d.clickEffect
        clickEffectSize = try c.decodeIfPresent(Double.self, forKey: .clickEffectSize) ?? d.clickEffectSize
        clickSound = (try? c.decodeIfPresent(ClickSound.self, forKey: .clickSound)) ?? d.clickSound
        clickSoundVolume = try c.decodeIfPresent(Double.self, forKey: .clickSoundVolume) ?? d.clickSoundVolume
        clickPress = try c.decodeIfPresent(Bool.self, forKey: .clickPress) ?? d.clickPress
        clickPressScale = try c.decodeIfPresent(Double.self, forKey: .clickPressScale) ?? d.clickPressScale
        clickPressDuration = try c.decodeIfPresent(Double.self, forKey: .clickPressDuration) ?? d.clickPressDuration
        loopPosition = try c.decodeIfPresent(Bool.self, forKey: .loopPosition) ?? d.loopPosition
        hideWhenIdle = try c.decodeIfPresent(Bool.self, forKey: .hideWhenIdle) ?? d.hideWhenIdle
        idleDelay = try c.decodeIfPresent(Double.self, forKey: .idleDelay) ?? d.idleDelay
    }

    private enum CodingKeys: String, CodingKey {
        case visible, size, style, smoothing, motionBlur, tilt, tiltMaxAngle, tiltSmoothing, stateDelay, clickEffect,
             clickEffectSize, clickSound, clickSoundVolume, clickPress, clickPressScale, clickPressDuration, loopPosition,
             hideWhenIdle, idleDelay
        case legacySmooth = "smooth"
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(visible, forKey: .visible)
        try c.encode(size, forKey: .size)
        try c.encode(style, forKey: .style)
        try c.encode(smoothing, forKey: .smoothing)
        try c.encode(motionBlur, forKey: .motionBlur)
        try c.encode(tilt, forKey: .tilt)
        try c.encode(tiltMaxAngle, forKey: .tiltMaxAngle)
        try c.encode(tiltSmoothing, forKey: .tiltSmoothing)
        try c.encode(stateDelay, forKey: .stateDelay)
        try c.encode(clickEffect, forKey: .clickEffect)
        try c.encode(clickEffectSize, forKey: .clickEffectSize)
        try c.encode(clickSound, forKey: .clickSound)
        try c.encode(clickSoundVolume, forKey: .clickSoundVolume)
        try c.encode(clickPress, forKey: .clickPress)
        try c.encode(clickPressScale, forKey: .clickPressScale)
        try c.encode(clickPressDuration, forKey: .clickPressDuration)
        try c.encode(loopPosition, forKey: .loopPosition)
        try c.encode(hideWhenIdle, forKey: .hideWhenIdle)
        try c.encode(idleDelay, forKey: .idleDelay)
    }

    var blurShutter: Double { min(max(motionBlur, 0), 1) / 60 }

    public func pressScale(ages: some Sequence<Double>) -> Double {
        guard clickPress, clickPressDuration > 0 else { return 1 }
        var depth = 0.0
        for age in ages where age >= 0 && age < clickPressDuration {
            let u = age / clickPressDuration, attack = 0.25
            let d: Double
            if u < attack {
                d = 1 - pow(1 - u / attack, 2)
            } else {
                let v = (u - attack) / (1 - attack)
                d = 1 - v * v * (3 - 2 * v)
            }
            depth = max(depth, d)
        }
        return 1 + (clickPressScale - 1) * depth
    }
}

/// The sound played at each recorded click. Raw values are saved in projects, so never rename them.
public enum ClickSound: String, Codable, CaseIterable {
    case none
    case magicMouse
    case deathAdder
    case tap

    public var label: String {
        switch self {
        case .none: "None"
        case .magicMouse: "Magic Mouse"
        case .deathAdder: "DeathAdder V2 Pro"
        case .tap: "Soft tap"
        }
    }

    public var detail: String {
        switch self {
        case .none: "Silent clicks"
        case .magicMouse: "Apple"
        case .deathAdder: "Razer"
        case .tap: "Interface"
        }
    }

    public var url: URL? {
        let file: String? = switch self {
        case .none: nil
        case .magicMouse: "magic-mouse"
        case .deathAdder: "deathadder-v2-pro"
        case .tap: "tap"
        }
        return file.flatMap { Bundle.module.url(forResource: $0, withExtension: "wav", subdirectory: "Sounds") }
    }
}

public enum ClickEffect: String, Codable, CaseIterable {
    case none
    case ripple
    case liquid

    public var label: String {
        switch self {
        case .none: "None"
        case .ripple: "Ripple"
        case .liquid: "Liquid"
        }
    }

    public var duration: Double {
        switch self {
        case .none: 0
        case .ripple: 0.55
        case .liquid: 0.6
        }
    }
}

/// A pointer look. `native`, `tahoe` and `macOS27` follow the recorded system cursor (hand over links, I-beam over text, resize
/// arrows...) with macOS artwork; the cute sets follow it too, with their own arrow and (most) a hand; the others always
/// draw one shape, as vector artwork that stays crisp at any size and zoom. Raw values are saved in projects, so
/// `native` and `macOS27` keep their names though they're labelled Big Sur and Golden Gate. A removed style (the plain
/// black and white arrows) reads as the default.
public enum CursorStyle: String, Codable, CaseIterable {
    case native
    case tahoe
    case macOS27
    case pompompurin, pizza, watermelon
    case dot

    public enum Family: CaseIterable {
        case macOS, cute, simple

        public var label: String {
            switch self {
            case .macOS: "macOS"
            case .cute: "Cute"
            case .simple: "Simple"
            }
        }
    }

    public var family: Family {
        switch self {
        case .native, .tahoe, .macOS27: .macOS
        case .pompompurin, .pizza, .watermelon: .cute
        case .dot: .simple
        }
    }

    public var label: String {
        switch self {
        case .native: "Big Sur"
        case .tahoe: "Tahoe"
        case .macOS27: "Golden Gate"
        case .pompompurin: "Pompompurin"
        case .pizza: "Pizza"
        case .watermelon: "Watermelon"
        case .dot: "Dot"
        }
    }

    public var followsSystemCursor: Bool { nativeSet != nil }

    var nativeSet: NativeCursor.Set? {
        switch self {
        case .native: .bigSur
        case .tahoe: .tahoe
        case .macOS27: .macOS27
        case .pompompurin: .pompompurin
        case .pizza: .pizza
        case .watermelon: .watermelon
        case .dot: nil
        }
    }

    var artwork: CursorArtwork? {
        self == .dot ? .dot : nil
    }
}

/// Which system cursor was showing, as recorded. Raw values are stored in cursor logs, so never rename them.
public enum CursorType: String, Codable, CaseIterable {
    case arrow
    case pointingHand
    case iBeam
    case iBeamVertical
    case crosshair
    case openHand
    case closedHand
    case contextualMenu
    case dragCopy
    case operationNotAllowed
    case zoomIn
    case zoomOut
    case resizeLeftRight, resizeLeft, resizeRight
    case resizeUpDown, resizeUp, resizeDown
    case resizeEastWest, resizeNorthSouth
    case resizeNorth, resizeSouth, resizeEast, resizeWest
    case resizeNorthEast, resizeNorthWest, resizeSouthEast, resizeSouthWest
    case resizeNorthEastSouthWest, resizeNorthWestSouthEast

    public init(from decoder: Decoder) throws {
        self = CursorType(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .arrow
    }
}
