//
//  MusicOrb.swift
//  Slice
//
//  Created by rit3zh CX on 10/16/26.
//

import SliceCore
import SwiftUI

/// A soft gradient orb standing in for a track's artwork. Each track gets its own hue and swirl;
/// while `drifting`, the colours slowly flow around the orb.
struct MusicOrb: View {
    let seed: UInt64
    let hue: Double
    var drifting = false

    init(source: MusicSource?, drifting: Bool = false) {
        seed = Self.seed(of: source)
        hue = Self.hue(of: source, seed: seed)
        self.drifting = drifting
    }

    var body: some View {
        SwiftUI.TimelineView(.animation(minimumInterval: 1 / 30, paused: !drifting)) { context in
            let t = drifting ? context.date.timeIntervalSinceReferenceDate : 0
            GeometryReader { geo in
                let d = min(geo.size.width, geo.size.height)
                MeshGradient(width: 3, height: 3, points: points(t), colors: colors, smoothsColors: true)
                    .overlay(RadialGradient(colors: [.white.opacity(0.35), .clear], center: UnitPoint(x: 0.32, y: 0.26),
                                            startRadius: 0, endRadius: d * 0.5))
                    .overlay(RadialGradient(colors: [.clear, .black.opacity(0.22)], center: .center,
                                            startRadius: d * 0.32, endRadius: d * 0.56))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: max(d / 40, 0.5)))
                    .frame(width: d, height: d)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    // MARK: - Shape

    private func points(_ t: Double) -> [SIMD2<Float>] {
        var rng = SeededRandom(seed)
        let phase = Double(rng.next() % 628) / 100
        let wobble = { (i: Double) -> SIMD2<Float> in
            let a = t * 0.6 + phase + i * 2.1
            return SIMD2(Float(cos(a) * 0.12), Float(sin(a * 1.3) * 0.12))
        }
        let jitter = { SIMD2(Float(rng.unit() - 0.5) * 0.36, Float(rng.unit() - 0.5) * 0.36) }
        let edgeX = { Float(0.5 + (rng.unit() - 0.5) * 0.4) }
        return [
            [0, 0], [edgeX(), 0], [1, 0],
            [0, edgeX()], SIMD2(0.5, 0.5) + jitter() + wobble(0), [1, edgeX()],
            [0, 1], [edgeX(), 1], [1, 1],
        ]
    }

    // MARK: - Colour

    private var colors: [Color] {
        let tone = { (shift: Double, s: Double, b: Double) in
            Color(hue: (hue + shift + 1).truncatingRemainder(dividingBy: 1), saturation: s, brightness: b)
        }
        let base = tone(0, 0.72, 1), warm = tone(0.1, 0.62, 1), cool = tone(-0.13, 0.8, 0.96)
        let light = tone(0.04, 0.16, 1), deep = tone(-0.03, 0.9, 0.72)
        var grid = [light, base, warm,
                    base, seed & 1 == 0 ? warm : cool, cool,
                    cool, deep, base]
        // Quarter-turn the layout so orbs of neighbouring hues still differ in shape.
        for _ in 0 ..< Int(seed >> 8 & 3) { grid = [6, 3, 0, 7, 4, 1, 8, 5, 2].map { grid[$0] } }
        return grid
    }

    /// Library tracks step round the colour wheel by the golden angle, so neighbours never share a hue;
    /// imported files take a hue from their path.
    private static func hue(of source: MusicSource?, seed: UInt64) -> Double {
        if case let .library(id) = source, let i = EditorModel.libraryTracks.firstIndex(where: { $0.id == id }) {
            return (0.6 + Double(i) * 0.618_034).truncatingRemainder(dividingBy: 1)
        }
        return Double(seed % 1000) / 1000
    }

    private static func seed(of source: MusicSource?) -> UInt64 {
        let key = switch source {
        case let .library(id): "library:\(id)"
        case let .file(path): "file:\(path)"
        case nil: "music"
        }
        // FNV-1a, so a track keeps its orb across launches (hashValue is reseeded every run).
        return key.utf8.reduce(0xCBF2_9CE4_8422_2325) { ($0 ^ UInt64($1)) &* 0x100_0000_01B3 }
    }
}

private struct SeededRandom {
    private var state: UInt64

    init(_ seed: UInt64) { state = seed | 1 }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func unit() -> Double { Double(next() % 10_000) / 10_000 }
}
