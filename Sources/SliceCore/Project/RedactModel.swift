//
//  RedactModel.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreGraphics
import Foundation

public enum RedactStyle: String, Codable, CaseIterable {
    case blur, pixelate

    public var label: String {
        switch self {
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        }
    }
}

/// A part of the screen hidden for a while. It's drawn into the recording itself, so it stays on what it covers
/// through zooms, tilts and the lens.
public struct RedactBlock: Codable, Equatable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    /// Fractions of the screen, with a top-left origin.
    public var rect: CGRect
    public var style: RedactStyle
    public var strength: Double
    /// Found by "Find sensitive text"; scanning again replaces these.
    public var isAuto: Bool
    /// What a scan found here, like "Email".
    public var label: String?

    public init(id: UUID = UUID(), start: Double, end: Double, rect: CGRect = CGRect(x: 0.35, y: 0.4, width: 0.3, height: 0.2),
                style: RedactStyle = .blur, strength: Double = 0.6, isAuto: Bool = false, label: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.rect = rect
        self.style = style
        self.strength = strength
        self.isAuto = isAuto
        self.label = label
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = RedactBlock(start: 0, end: 0)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        rect = try c.decodeIfPresent(CGRect.self, forKey: .rect) ?? d.rect
        style = (try? c.decodeIfPresent(RedactStyle.self, forKey: .style)) ?? d.style
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? d.strength
        isAuto = try c.decodeIfPresent(Bool.self, forKey: .isAuto) ?? false
        label = try c.decodeIfPresent(String.self, forKey: .label)
    }

    public func isActive(at t: Double) -> Bool { t >= start && t < end }

    public static let minSize = 0.01

    /// `rect` kept inside the screen and at least a sliver big.
    public static func clamped(_ r: CGRect) -> CGRect {
        let w = min(max(r.width, minSize), 1), h = min(max(r.height, minSize), 1)
        return CGRect(x: min(max(r.minX, 0), 1 - w), y: min(max(r.minY, 0), 1 - h), width: w, height: h)
    }
}

extension Project {
    public func redactions(at t: Double) -> [RedactBlock] { redactions.filter { $0.isActive(at: t) } }
}
