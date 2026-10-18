//
//  ColorMath.swift
//  Slice
//
//  Created by rit3zh CX on 10/18/26.
//

import Foundation
import SliceCore

/// A colour as the picker edits it. Hue is kept even when saturation or brightness is zero, so dragging through grey
/// or black doesn't lose it. Channels are 0...1, hue is degrees.
struct HSVA: Equatable {
    var h: Double
    var s: Double
    var v: Double
    var a: Double = 1

    init(h: Double, s: Double, v: Double, a: Double = 1) {
        self.h = h
        self.s = s
        self.v = v
        self.a = a
    }

    init(_ c: RGBA, hue: Double = 0) {
        let maxC = max(c.r, c.g, c.b), minC = min(c.r, c.g, c.b), d = maxC - minC
        var h = hue
        if d > 1e-6 {
            if maxC == c.r { h = 60 * ((c.g - c.b) / d).truncatingRemainder(dividingBy: 6) }
            else if maxC == c.g { h = 60 * ((c.b - c.r) / d + 2) }
            else { h = 60 * ((c.r - c.g) / d + 4) }
            if h < 0 { h += 360 }
        }
        self.init(h: h, s: maxC == 0 ? 0 : d / maxC, v: maxC, a: c.a)
    }

    var rgba: RGBA {
        func f(_ n: Double) -> Double {
            let k = (n + h / 60).truncatingRemainder(dividingBy: 6)
            return v - v * s * max(0, min(k, 4 - k, 1))
        }
        return RGBA(f(5), f(3), f(1), a)
    }

    /// The fully saturated, fully bright colour at this hue, for the area's backdrop.
    var pure: RGBA { HSVA(h: h, s: 1, v: 1).rgba }

    var hex: String {
        let c = rgba
        return "#" + [c.r, c.g, c.b].map { String(format: "%02X", Self.byte($0)) }.joined()
    }

    func text(_ format: ColorFormat) -> String {
        let c = rgba
        switch format {
        case .hex:
            return hex
        case .rgb:
            return "\(Self.byte(c.r)), \(Self.byte(c.g)), \(Self.byte(c.b))"
        case .hsl:
            let (h, s, l) = Self.hsl(c, hue: h)
            return "\(Int(h.rounded()) % 360)°, \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%"
        case .oklch:
            let (l, ch, h) = Self.oklch(c, hue: h)
            return String(format: "%.1f%%, %.3f, %.1f°", l * 100, ch, h.truncatingRemainder(dividingBy: 360))
        }
    }

    static func byte(_ c: Double) -> Int { Int((min(max(c, 0), 1) * 255).rounded()) }

    // MARK: Other spaces

    private static func hsl(_ c: RGBA, hue: Double) -> (Double, Double, Double) {
        let maxC = max(c.r, c.g, c.b), minC = min(c.r, c.g, c.b), l = (maxC + minC) / 2, d = maxC - minC
        let s = d < 1e-6 ? 0 : d / (1 - abs(2 * l - 1))
        return (d < 1e-6 ? hue : HSVA(c).h, s, l)
    }

    private static func fromHSL(h: Double, s: Double, l: Double) -> RGBA {
        let c = s * min(l, 1 - l)
        func f(_ n: Double) -> Double {
            let k = (n + h / 30).truncatingRemainder(dividingBy: 12)
            return l - c * max(-1, min(k - 3, 9 - k, 1))
        }
        return RGBA(f(0), f(8), f(4))
    }

    private static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func gamma(_ c: Double) -> Double { c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    private static func oklch(_ c: RGBA, hue: Double) -> (Double, Double, Double) {
        let r = linear(c.r), g = linear(c.g), b = linear(c.b)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s
        let A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s
        let B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s
        let C = hypot(A, B)
        var H = atan2(B, A) * 180 / .pi
        if H < 0 { H += 360 }
        return (L, C, C < 0.0005 ? hue : H)
    }

    private static func fromOKLCH(l L: Double, c C: Double, h H: Double) -> RGBA {
        let A = C * cos(H * .pi / 180), B = C * sin(H * .pi / 180)
        let l = pow(L + 0.3963377774 * A + 0.2158037573 * B, 3)
        let m = pow(L - 0.1055613458 * A - 0.0638541728 * B, 3)
        let s = pow(L - 0.0894841775 * A - 1.291485548 * B, 3)
        func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
        return RGBA(clamp(gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)),
                    clamp(gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)),
                    clamp(gamma(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s)))
    }

    // MARK: Reading

    /// Reads what someone types in any of the formats: hex with or without #, or the format's numbers separated by
    /// commas or spaces (with or without the rgb(…)/hsl(…)/oklch(…) wrapper). Nil for anything else.
    static func parse(_ input: String, as format: ColorFormat, hue: Double) -> HSVA? {
        var text = input.trimmingCharacters(in: .whitespaces).lowercased()
        if let hex = parseHex(text) { return HSVA(hex, hue: hue) }
        for name in ["rgba", "rgb", "hsla", "hsl", "oklch"] where text.hasPrefix(name + "(") {
            text = String(text.dropFirst(name.count + 1).dropLast(text.hasSuffix(")") ? 1 : 0))
        }
        let numbers = text.split(whereSeparator: { ", /°%".contains($0) }).compactMap { Double($0) }
        guard numbers.count >= 3 else { return nil }
        let (x, y, z) = (numbers[0], numbers[1], numbers[2])
        switch format {
        case .hex, .rgb:
            return HSVA(RGBA(min(x, 255) / 255, min(y, 255) / 255, min(z, 255) / 255), hue: hue)
        case .hsl:
            let h = x.truncatingRemainder(dividingBy: 360)
            var next = HSVA(fromHSL(h: h, s: min(y, 100) / 100, l: min(z, 100) / 100), hue: h)
            next.h = h
            return next
        case .oklch:
            return HSVA(fromOKLCH(l: x > 1 ? x / 100 : x, c: y, h: z), hue: hue)
        }
    }

    private static func parseHex(_ text: String) -> RGBA? {
        var digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
        guard [3, 6].contains(digits.count), digits.allSatisfy(\.isHexDigit) else { return nil }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard let n = Int(digits, radix: 16) else { return nil }
        return RGBA(Double((n >> 16) & 0xFF) / 255, Double((n >> 8) & 0xFF) / 255, Double(n & 0xFF) / 255)
    }
}

enum ColorFormat: String, CaseIterable {
    case hex, rgb, hsl, oklch

    var name: String {
        switch self {
        case .hex: "Hex"
        case .rgb: "RGB"
        case .hsl: "HSL"
        case .oklch: "OKLCH"
        }
    }

    var next: ColorFormat { Self.allCases[(Self.allCases.firstIndex(of: self)! + 1) % Self.allCases.count] }
}
