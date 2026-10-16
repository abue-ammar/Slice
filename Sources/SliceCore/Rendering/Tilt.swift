//
//  Tilt.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/13/26.
//

import CoreGraphics
import Foundation

public enum TiltDirection: String, Codable, CaseIterable {
    case left, right

    public var label: String {
        switch self {
        case .left: "Left"
        case .right: "Right"
        }
    }
}

public struct ZoomTilt: Codable, Equatable {
    public var enabled = false
    public var direction: TiltDirection = .right
    public var strength = 0.5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ZoomTilt()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? d.enabled
        direction = (try? c.decodeIfPresent(TiltDirection.self, forKey: .direction)) ?? d.direction
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? d.strength
    }

    public static let maxAngle = 30.0
    static let pitchShare = 0.2

    public var pose: ScreenTilt {
        guard enabled else { return .flat }
        let yaw = min(max(strength, 0), 1) * Self.maxAngle * .pi / 180 * (direction == .right ? 1 : -1)
        return ScreenTilt(yaw: yaw, pitch: -abs(yaw) * Self.pitchShare)
    }
}

public struct ScreenTilt: Interpolatable, Equatable {
    public var yaw: Double
    public var pitch: Double

    public init(yaw: Double, pitch: Double) {
        self.yaw = yaw
        self.pitch = pitch
    }

    public static let flat = ScreenTilt(yaw: 0, pitch: 0)

    public var isFlat: Bool { abs(yaw) < 1e-6 && abs(pitch) < 1e-6 }

    public static func interpolate(_ a: ScreenTilt, _ b: ScreenTilt, _ t: Double) -> ScreenTilt {
        ScreenTilt(yaw: lerp(a.yaw, b.yaw, t), pitch: lerp(a.pitch, b.pitch, t))
    }

    static let focalLength = 1.5
    static let floatInset = 0.25

    public func homography(output: CGSize) -> Homography {
        let w = Double(output.width), h = Double(output.height)
        let focal = Self.focalLength * max(w, h)
        let (ca, sa) = (cos(yaw), sin(yaw))
        let (cb, sb) = (cos(pitch), sin(pitch))
        let ax = (x: ca, y: 0.0, z: sa)
        let ay = (x: -sb * sa, y: cb, z: sb * ca)
        let inset = 1 - Self.floatInset * abs(sa)
        let depth = focal * ca / inset - focal + w / 2 * abs(sa)
        let relative = Homography(m: [
            focal * ax.x, focal * ay.x, 0,
            focal * ax.y, focal * ay.y, 0,
            ax.z, ay.z, focal + depth,
        ])
        return Homography.translation(w / 2, h / 2) * relative * Homography.translation(-w / 2, -h / 2)
    }
}

public struct Homography: Equatable {
    public var m: [Double]

    public init(m: [Double]) { self.m = m }

    static func translation(_ x: Double, _ y: Double) -> Homography { Homography(m: [1, 0, x, 0, 1, y, 0, 0, 1]) }

    static func * (a: Homography, b: Homography) -> Homography {
        var out = [Double](repeating: 0, count: 9)
        for r in 0 ..< 3 { for c in 0 ..< 3 { for k in 0 ..< 3 { out[r * 3 + c] += a.m[r * 3 + k] * b.m[k * 3 + c] } } }
        return Homography(m: out)
    }

    public func apply(_ p: CGPoint) -> CGPoint? {
        let x = Double(p.x), y = Double(p.y)
        let z = m[6] * x + m[7] * y + m[8]
        guard z > 1e-9 else { return nil }
        return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / z, y: (m[3] * x + m[4] * y + m[5]) / z)
    }

    public var inverse: Homography? {
        let a = m
        let c00 = a[4] * a[8] - a[5] * a[7], c01 = a[5] * a[6] - a[3] * a[8], c02 = a[3] * a[7] - a[4] * a[6]
        let det = a[0] * c00 + a[1] * c01 + a[2] * c02
        guard abs(det) > 1e-12 else { return nil }
        let inv = [
            c00, a[2] * a[7] - a[1] * a[8], a[1] * a[5] - a[2] * a[4],
            c01, a[0] * a[8] - a[2] * a[6], a[2] * a[3] - a[0] * a[5],
            c02, a[1] * a[6] - a[0] * a[7], a[0] * a[4] - a[1] * a[3],
        ].map { $0 / det }
        return Homography(m: inv)
    }

    public func bounds(of rect: CGRect) -> CGRect? {
        let corners = [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
                       CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)].map(apply)
        guard corners.allSatisfy({ $0 != nil }) else { return nil }
        return corners.compactMap { $0 }.reduce(CGRect.null) { $0.union(CGRect(origin: $1, size: .zero)) }
    }
}
