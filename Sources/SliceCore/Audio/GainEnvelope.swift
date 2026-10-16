//
//  GainEnvelope.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/1/26.
//

import Foundation

public struct GainEnvelope: Equatable {
    public struct Point: Equatable {
        public var t: Double
        public var gain: Double
        public init(t: Double, gain: Double) { self.t = t; self.gain = gain }
    }

    public private(set) var points: [Point]

    public init(_ points: [Point]) {
        self.points = points.enumerated().sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }.map(\.element)
    }

    public static func constant(_ gain: Double) -> GainEnvelope { GainEnvelope([Point(t: 0, gain: gain)]) }

    public func value(at t: Double) -> Double {
        guard let first = points.first else { return 1 }
        if t <= first.t { return first.gain }
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if points[mid].t <= t { lo = mid } else { hi = mid - 1 }
        }
        guard lo + 1 < points.count else { return points[lo].gain }
        let a = points[lo], b = points[lo + 1]
        guard b.t - a.t > 1e-12 else { return b.gain }
        return a.gain + (b.gain - a.gain) * (t - a.t) / (b.t - a.t)
    }

    public static func * (l: GainEnvelope, r: GainEnvelope) -> GainEnvelope {
        if l.points.count <= 1 { return r.scaled(l.points.first?.gain ?? 1) }
        if r.points.count <= 1 { return l.scaled(r.points.first?.gain ?? 1) }
        let times = Array(Set(l.points.map(\.t) + r.points.map(\.t))).sorted()
        return GainEnvelope(times.map { Point(t: $0, gain: l.value(at: $0) * r.value(at: $0)) }).simplified()
    }

    public func scaled(_ k: Double) -> GainEnvelope {
        var e = self
        for i in e.points.indices { e.points[i].gain *= k }
        return e
    }

    public func clamped(to range: ClosedRange<Double>) -> GainEnvelope {
        var e = self
        for i in e.points.indices { e.points[i].gain = min(max(e.points[i].gain, range.lowerBound), range.upperBound) }
        return e
    }

    func simplified() -> GainEnvelope {
        guard points.count > 2 else { return self }
        var out = [points[0]]
        for i in 1 ..< points.count - 1 {
            let a = out.last!, p = points[i], b = points[i + 1]
            let span = b.t - a.t
            let line = span > 1e-12 ? a.gain + (b.gain - a.gain) * (p.t - a.t) / span : p.gain
            if abs(line - p.gain) > 1e-5 { out.append(p) }
        }
        out.append(points[points.count - 1])
        return GainEnvelope(out)
    }

    static func ramp(from t0: Double, _ g0: Double, to t1: Double, _ g1: Double, curve: (Double) -> Double = { $0 },
                     steps: Int = 8) -> [Point] {
        guard t1 - t0 > 1e-9 else { return [Point(t: t0, gain: g0), Point(t: t0 + 1e-6, gain: g1)] }
        return (0 ... steps).map { i in
            let x = Double(i) / Double(steps)
            return Point(t: t0 + (t1 - t0) * x, gain: g0 + (g1 - g0) * curve(x))
        }
    }

    public static func ducking(spans: [TimeSpan], level: Double, attack: Double, release: Double,
                               hold: Double = 0.15) -> GainEnvelope {
        let attack = max(attack, 0.02), release = max(release, 0.02)
        var merged: [TimeSpan] = []
        for s in spans.sorted(by: { $0.start < $1.start }) where s.end > s.start {
            if let last = merged.last, s.start - attack <= last.end + hold + release {
                merged[merged.count - 1].end = max(last.end, s.end)
            } else {
                merged.append(s)
            }
        }
        guard !merged.isEmpty else { return .constant(1) }
        let smooth = MusicClip.fadeCurve
        var points: [Point] = []
        for s in merged {
            points += ramp(from: s.start - attack, 1, to: s.start, level, curve: smooth, steps: 6)
            points += ramp(from: s.end + hold, level, to: s.end + hold + release, 1, curve: smooth, steps: 6)
        }
        return GainEnvelope(points)
    }

    static func joins(_ joins: [Double], level: Double, fade: Double = 0.012) -> GainEnvelope {
        guard level > 0, !joins.isEmpty else { return .constant(level) }
        var points: [Point] = []
        for j in joins {
            points += [Point(t: j - fade, gain: level), Point(t: j, gain: 0), Point(t: j + fade, gain: level)]
        }
        return GainEnvelope(points)
    }

    static func crossfade(pieces: [MusicPiece], lane: Int) -> GainEnvelope {
        let rise: (Double) -> Double = { sin($0 * .pi / 2) }
        var points: [Point] = []
        for (i, p) in pieces.enumerated() where p.lane == lane {
            let incoming = i > 0 ? max(pieces[i - 1].end - p.at, 0) : 0
            let outgoing = i + 1 < pieces.count ? max(p.end - pieces[i + 1].at, 0) : 0
            if incoming > 0 { points += ramp(from: p.at, 0, to: p.at + incoming, 1, curve: rise, steps: 6) }
            else { points.append(Point(t: p.at, gain: 1)) }
            if outgoing > 0 { points += ramp(from: p.end - outgoing, 1, to: p.end, 0, curve: { 1 - rise(1 - $0) }, steps: 6) }
            else { points.append(Point(t: p.end, gain: 1)) }
        }
        return points.isEmpty ? .constant(1) : GainEnvelope(points)
    }
}
