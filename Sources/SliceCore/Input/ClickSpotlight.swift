//
//  ClickSpotlight.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreGraphics
import Foundation

/// How the screen around a click is quietened. Raw values are saved in projects, so never rename them.
public enum SpotlightMode: String, Codable, CaseIterable {
    case dim
    case blur

    public var label: String {
        switch self {
        case .dim: "Dim"
        case .blur: "Blur"
        }
    }

    public var symbol: String {
        switch self {
        case .dim: "circle.lefthalf.filled"
        case .blur: "drop.halffull"
        }
    }

    func look(strength: Double) -> (darkness: Double, blur: Double) {
        let s = min(max(strength, 0), 1)
        return switch self {
        case .dim: (ClickSpotlight.dimDarkness * s, 0)
        case .blur: (ClickSpotlight.blurShade * s, s)
        }
    }
}

public struct ClickSpotlight: Codable, Equatable {
    public var enabled = false
    public var mode: SpotlightMode = .dim
    public var size = 1.0
    public var strength = 0.55
    public var hold = 0.9

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ClickSpotlight()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        mode = (try? c.decodeIfPresent(SpotlightMode.self, forKey: .mode)) ?? d.mode
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? d.strength
        hold = try c.decodeIfPresent(Double.self, forKey: .hold) ?? d.hold
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, mode, size, strength, hold
    }

    /// In the recorded screen's points, so it covers about the same control on any display.
    public static let radius: CGFloat = 150
    static let core: CGFloat = 0.5
    static let lead = 0.12
    static let fadeIn = 0.34
    static let fadeOut = 0.6
    static let glide = 0.38
    static let dimDarkness = 0.72
    static let blurPoints = 16.0
    static let blurShade = 0.16
    static let iris: CGFloat = 0.45

    var holdTime: Double { max(hold, fadeInEnd) }
    var fadeInEnd: Double { Self.fadeIn - Self.lead }

    func envelope(age: Double) -> (rise: Double, stay: Double) {
        guard lasts(age) else { return (0, 0) }
        let rise = smootherstep((age + Self.lead) / Self.fadeIn)
        let stay = 1 - smootherstep((age - holdTime) / Self.fadeOut)
        return (rise, stay)
    }

    func lasts(_ age: Double) -> Bool { age >= -Self.lead && age < holdTime + Self.fadeOut }
}

public struct SpotlightState: Equatable {
    public var center: CGPoint
    public var amount: Double
    public var size: Double
    /// How much darker the outside looks, and how blurred (0...1), when fully in.
    public var darkness: Double
    public var blur: Double

    static func interpolate(_ a: SpotlightState, _ b: SpotlightState, _ f: Double) -> SpotlightState {
        SpotlightState(center: CGPoint(x: lerp(a.center.x, b.center.x, f), y: lerp(a.center.y, b.center.y, f)),
                       amount: lerp(a.amount, b.amount, f), size: lerp(a.size, b.size, f),
                       darkness: lerp(a.darkness, b.darkness, f), blur: lerp(a.blur, b.blur, f))
    }
}

extension RenderScene {
    /// The click spotlight at `t`. A click that lands while the circle is still showing hands it on: the circle glides
    /// over to it rather than fading out and in again.
    func clickSpotlight(at t: Double) -> SpotlightState? {
        let settings = project.cursor.spotlight
        guard settings.enabled else { return nil }
        var center: CGPoint?
        var amount = 0.0
        var showingUntil = -Double.infinity
        for click in cursor.clicks {
            let start = click.t - ClickSpotlight.lead
            if start > t { break }
            if let from = center, start < showingUntil {
                let f = smootherstep((t - start) / ClickSpotlight.glide)
                center = CGPoint(x: lerp(from.x, click.point.x, f), y: lerp(from.y, click.point.y, f))
            } else {
                center = click.point
            }
            let age = t - click.t
            let e = settings.envelope(age: age)
            amount = max(amount, e.rise * e.stay)
            showingUntil = click.t + settings.holdTime + ClickSpotlight.fadeOut
        }
        guard let center, amount > 0.001 else { return nil }
        let look = settings.mode.look(strength: settings.strength)
        return SpotlightState(center: center, amount: amount, size: settings.size, darkness: look.darkness, blur: look.blur)
    }
}

func smootherstep(_ x: Double) -> Double {
    let f = min(max(x, 0), 1)
    return f * f * f * (f * (f * 6 - 15) + 10)
}
