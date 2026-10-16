//
//  ZoomModel.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import CoreGraphics
import Foundation

public enum ZoomKind: String, Codable, CaseIterable {
    case standard
    case liquidGlass

    public var label: String {
        switch self {
        case .standard: "Default"
        case .liquidGlass: "Liquid Glass"
        }
    }
}

public enum EasingCurve: String, Codable, CaseIterable {
    case smooth
    case gentle
    case snappy
    case spring
    case easeIn
    case easeOut
    case linear
    case custom

    public var label: String {
        switch self {
        case .smooth: "Smooth"
        case .gentle: "Gentle"
        case .snappy: "Snappy"
        case .spring: "Spring"
        case .easeIn: "Ease in"
        case .easeOut: "Ease out"
        case .linear: "Linear"
        case .custom: "Custom"
        }
    }

    public func callAsFunction(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        switch self {
        case .smooth:
            // The integral of 105x²(1-x)⁴: speed, acceleration and jerk are all zero at the start and at the end, and
            // speed peaks a third of the way in, so most of the move is a long, even slow-down.
            let x2 = x * x
            return x2 * x * (35 + x * (-105 + x * (126 + x * (-70 + x * 15))))
        case .gentle: return -(cos(.pi * x) - 1) / 2
        case .snappy: return x >= 1 ? 1 : 1 - pow(2, -10 * x)
        case .spring:
            let w = 8.0
            return (1 - (1 + w * x) * exp(-w * x)) / (1 - (1 + w) * exp(-w))
        case .easeIn: return x * x * x
        case .easeOut: return 1 - pow(1 - x, 3)
        case .linear: return x
        case .custom: return CubicBezier.default(x)
        }
    }
}

public struct CubicBezier: Codable, Equatable, Hashable {
    public var x1, y1, x2, y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = min(max(x1, 0), 1)
        self.y1 = y1
        self.x2 = min(max(x2, 0), 1)
        self.y2 = y2
    }

    public static let `default` = CubicBezier(0.23, 1, 0.32, 1)

    public func callAsFunction(_ x: Double) -> Double {
        let x = min(max(x, 0), 1)
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        // Find the curve parameter whose time is x: Newton's method, falling back to bisection (time is monotonic in
        // the parameter because both handle times are in 0...1).
        func coordinate(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        func slope(_ t: Double, _ a: Double, _ b: Double) -> Double {
            let u = 1 - t
            return 3 * u * u * a + 6 * u * t * (b - a) + 3 * t * t * (1 - b)
        }
        var t = x
        for _ in 0 ..< 8 {
            let error = coordinate(t, x1, x2) - x
            if abs(error) < 1e-7 { return coordinate(t, y1, y2) }
            let d = slope(t, x1, x2)
            if abs(d) < 1e-6 { break }
            t = min(max(t - error / d, 0), 1)
        }
        var lo = 0.0, hi = 1.0
        t = x
        for _ in 0 ..< 40 {
            let value = coordinate(t, x1, x2)
            if abs(value - x) < 1e-7 { break }
            if value < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return coordinate(t, y1, y2)
    }

    public var css: String {
        func number(_ v: Double) -> String {
            let rounded = (v * 1000).rounded() / 1000
            return rounded == rounded.rounded() ? String(Int(rounded)) : String(rounded)
        }
        return "cubic-bezier(\([x1, y1, x2, y2].map(number).joined(separator: ", ")))"
    }

    public init?(css: String) {
        var text = css.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("cubic-bezier") { text.removeFirst("cubic-bezier".count) }
        let numbers = text.split(whereSeparator: { ",() \t;".contains($0) }).compactMap { Double($0) }
        guard numbers.count == 4, (0 ... 1).contains(numbers[0]), (0 ... 1).contains(numbers[2]) else { return nil }
        self.init(numbers[0], numbers[1], numbers[2], numbers[3])
    }

    public static let presets: [(name: String, curve: CubicBezier, use: String)] = [
        ("ease-out", CubicBezier(0.23, 1, 0.32, 1),
         "Arrives fast and lands softly. Feels instant, so it suits zooms that answer a click."),
        ("ease-in-out", CubicBezier(0.77, 0, 0.175, 1),
         "Speeds up, then settles. A deliberate camera move from one place to another."),
        ("iOS drawer", CubicBezier(0.32, 0.72, 0, 1),
         "The curve iOS sheets slide in with: quick, with a long gentle landing."),
        ("ease", CubicBezier(0.25, 0.1, 0.25, 1),
         "The CSS default. Soft and unhurried; can feel a little floaty for big zooms."),
        ("linear", CubicBezier(0, 0, 1, 1),
         "Constant speed. Mechanical for a camera, but useful for slow, steady drifts."),
        ("overshoot", CubicBezier(0.34, 1.56, 0.64, 1),
         "Zooms a touch past the target, then eases back. Playful; use sparingly."),
    ]
}

public enum LensShape: String, Codable, CaseIterable {
    case circle, squircle, pill

    public var label: String {
        switch self {
        case .circle: "Circle"
        case .squircle: "Squircle"
        case .pill: "Pill"
        }
    }
}

public struct LensSettings: Codable, Equatable {
    public var size = 0.6
    public var shape: LensShape = .circle
    public var refraction = 0.45
    public var thickness = 0.3
    public var dispersion = 0.2
    public var blur = 0.0
    public var rim = 0.7
    public var shadow = 0.5
    public var opacity = 1.0

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LensSettings()
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        shape = (try? c.decodeIfPresent(LensShape.self, forKey: .shape)) ?? d.shape
        refraction = try c.decodeIfPresent(Double.self, forKey: .refraction) ?? d.refraction
        thickness = try c.decodeIfPresent(Double.self, forKey: .thickness) ?? d.thickness
        dispersion = try c.decodeIfPresent(Double.self, forKey: .dispersion) ?? d.dispersion
        blur = try c.decodeIfPresent(Double.self, forKey: .blur) ?? d.blur
        rim = try c.decodeIfPresent(Double.self, forKey: .rim) ?? d.rim
        shadow = try c.decodeIfPresent(Double.self, forKey: .shadow) ?? d.shadow
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? d.opacity
    }
}

public struct ZoomBlock: Codable, Equatable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var scale: Double
    public var focus: CGPoint
    public var endFocus: CGPoint?
    public var followsCursor: Bool
    public var kind: ZoomKind
    public var transition: Double?
    public var easing: EasingCurve
    public var curve: CubicBezier
    public var lens: LensSettings
    public var tilt: ZoomTilt
    public var isAuto: Bool

    public init(id: UUID = UUID(), start: Double, end: Double, scale: Double = 2, focus: CGPoint = CGPoint(x: 0.5, y: 0.5),
                isAuto: Bool = false, kind: ZoomKind = .standard) {
        self.id = id
        self.start = start
        self.end = end
        self.scale = scale
        self.focus = focus
        self.isAuto = isAuto
        self.kind = kind
        endFocus = nil
        followsCursor = false
        transition = nil
        easing = .smooth
        curve = .default
        lens = LensSettings()
        tilt = ZoomTilt()
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 2
        focus = try c.decodeIfPresent(CGPoint.self, forKey: .focus) ?? CGPoint(x: 0.5, y: 0.5)
        endFocus = try c.decodeIfPresent(CGPoint.self, forKey: .endFocus)
        followsCursor = try c.decodeIfPresent(Bool.self, forKey: .followsCursor) ?? false
        kind = (try? c.decodeIfPresent(ZoomKind.self, forKey: .kind)) ?? .standard
        transition = try c.decodeIfPresent(Double.self, forKey: .transition)
        easing = (try? c.decodeIfPresent(EasingCurve.self, forKey: .easing)) ?? .smooth
        curve = (try? c.decodeIfPresent(CubicBezier.self, forKey: .curve)) ?? .default
        lens = try c.decodeIfPresent(LensSettings.self, forKey: .lens) ?? LensSettings()
        tilt = try c.decodeIfPresent(ZoomTilt.self, forKey: .tilt) ?? ZoomTilt()
        isAuto = try c.decodeIfPresent(Bool.self, forKey: .isAuto) ?? false
    }

    public func ease(_ x: Double) -> Double { easing == .custom ? curve(x) : easing(x) }

    public func target(progress: Double) -> CGPoint {
        guard let end = endFocus else { return focus }
        return CGPoint(x: focus.x + (end.x - focus.x) * progress, y: focus.y + (end.y - focus.y) * progress)
    }
}
