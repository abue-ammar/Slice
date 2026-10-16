//
//  CursorMotion.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/5/26.
//

import CoreGraphics
import Foundation

/// Turns a recorded mouse path into the one drawn on screen.
///
/// Zero-phase Gaussian smoothing whose width adapts to speed: wide while the pointer creeps or rests (removing hand
/// tremor and sensor jitter), narrow during quick moves (so they keep their shape and pace). The kernel is symmetric,
/// so steady motion passes through unchanged and the pointer never trails behind the recording.
///
/// Smoothing must never put the pointer somewhere the footage disagrees with: a menu row lighting up while the drawn
/// pointer is still on the row above reads as lag. So around hover moments (the interface reacting to the pointer, see
/// `HoverDetector`) the width drops to about a frame, and the path is pinned to the exact recorded position at each
/// hover and each click, so the hotspot is on target whenever the picture depends on it. Elsewhere it stays smooth.
public struct CursorSmoother {
    public var slowWidth = 0.11
    public var fastWidth = 0.045
    public var slowSpeed = 80.0
    public var fastSpeed = 900.0
    public var reach = 0.15
    public var pinWidth = 0.08
    public var hoverWidth = 0.012
    public var hoverReach = 0.12
    public var hoverPinWidth = 0.045
    public var isOff = false

    public init() {}

    public init(strength: Double) {
        let s = min(max(strength, 0), 1) * 2
        slowWidth *= s
        fastWidth *= s
        isOff = s < 0.01
    }

    public func smooth(_ points: [CGPoint], rate: Double, pointSize: CGSize, pins: [(t: Double, point: CGPoint)],
                       hovers: [Double] = []) -> [CGPoint] {
        let n = points.count
        guard n > 2, rate > 0, !isOff else { return points }
        let xs = points.map { Double($0.x) }, ys = points.map { Double($0.y) }

        let pre = [Double](repeating: 0.02 * rate, count: n)
        let px = Self.gaussian(xs, widths: pre), py = Self.gaussian(ys, widths: pre)
        var speed = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            let a = max(i - 1, 0), b = min(i + 1, n - 1)
            let dx = (px[b] - px[a]) * pointSize.width, dy = (py[b] - py[a]) * pointSize.height
            speed[i] = (dx * dx + dy * dy).squareRoot() * rate / Double(b - a)
        }
        let envelope = Self.slidingMax(speed, radius: Int((reach * rate).rounded()))
        let span = max(fastSpeed - slowSpeed, 1)
        var base = envelope.map { v in
            let f = min(max((v - slowSpeed) / span, 0), 1)
            return (slowWidth + (fastWidth - slowWidth) * f * f * (3 - 2 * f)) * rate
        }
        let reachSamples = hoverReach * rate
        for h in hovers where reachSamples > 0 {
            let f = h * rate
            guard f >= -3 * reachSamples, f <= Double(n - 1) + 3 * reachSamples else { continue }
            for j in max(Int(f - 3 * reachSamples), 0) ... min(Int(f + 3 * reachSamples) + 1, n - 1) {
                let d = (Double(j) - f) / reachSamples
                let near = exp(-0.5 * d * d)
                base[j] = min(base[j], base[j] + (hoverWidth * rate - base[j]) * near)
            }
        }
        let widths = Self.boxBlur(base, radius: Int((0.05 * rate).rounded()))
        var sx = Self.gaussian(xs, widths: widths), sy = Self.gaussian(ys, widths: widths)

        func recorded(_ f: Double) -> CGPoint {
            let i = min(max(Int(f), 0), n - 1), k = min(i + 1, n - 1), frac = min(max(f - Double(i), 0), 1)
            return CGPoint(x: xs[i] + (xs[k] - xs[i]) * frac, y: ys[i] + (ys[k] - ys[i]) * frac)
        }
        var targets = pins.map { (f: $0.t * rate, point: $0.point, width: pinWidth * rate) }
        targets += hovers.map { (f: $0 * rate, point: recorded($0 * rate), width: hoverPinWidth * rate) }
        targets = targets.filter { $0.f >= 0 && $0.f <= Double(n - 1) && $0.width > 0 }.sorted { $0.f < $1.f }
        for _ in 0 ..< (targets.count > 1 ? 4 : 1) {
            for p in targets {
                let i = Int(p.f), k = min(i + 1, n - 1), frac = p.f - Double(i)
                let ex = Double(p.point.x) - (sx[i] + (sx[k] - sx[i]) * frac)
                let ey = Double(p.point.y) - (sy[i] + (sy[k] - sy[i]) * frac)
                guard abs(ex) + abs(ey) > 1e-7 else { continue }
                for j in max(Int(p.f - 3 * p.width), 0) ... min(Int(p.f + 3 * p.width) + 1, n - 1) {
                    let d = (Double(j) - p.f) / p.width
                    let w = exp(-0.5 * d * d)
                    sx[j] += ex * w
                    sy[j] += ey * w
                }
            }
        }
        return (0 ..< n).map { CGPoint(x: sx[$0], y: sy[$0]) }
    }

    static func gaussian(_ v: [Double], widths: [Double]) -> [Double] {
        let n = v.count
        guard n > 1 else { return v }
        func value(_ j: Int) -> Double {
            if j < 0 { return 2 * v[0] - v[min(-j, n - 1)] }
            if j >= n { return 2 * v[n - 1] - v[max(2 * (n - 1) - j, 0)] }
            return v[j]
        }
        var kernels: [Int: [Double]] = [:]
        var out = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            let key = Int((widths[i] * 4).rounded())
            let kernel: [Double]
            if let k = kernels[key] {
                kernel = k
            } else {
                kernel = Self.kernel(sigma: Double(key) / 4)
                kernels[key] = kernel
            }
            var sum = v[i] * kernel[0]
            for d in 1 ..< kernel.count { sum += kernel[d] * (value(i - d) + value(i + d)) }
            out[i] = sum
        }
        return out
    }

    private static func kernel(sigma: Double) -> [Double] {
        guard sigma > 0.1 else { return [1] }
        let r = Int((3 * sigma).rounded(.up))
        var w = (0 ... r).map { d in exp(-Double(d * d) / (2 * sigma * sigma)) }
        let total = w[0] + 2 * w.dropFirst().reduce(0, +)
        for d in w.indices { w[d] /= total }
        return w
    }

    private static func slidingMax(_ v: [Double], radius: Int) -> [Double] {
        v.indices.map { i in v[max(i - radius, 0) ... min(i + radius, v.count - 1)].max() ?? 0 }
    }

    private static func boxBlur(_ v: [Double], radius: Int) -> [Double] {
        guard radius > 0, !v.isEmpty else { return v }
        var prefix = [0.0]
        prefix.reserveCapacity(v.count + 1)
        for x in v { prefix.append(prefix.last! + x) }
        return v.indices.map { i in
            let a = max(i - radius, 0), b = min(i + radius, v.count - 1)
            return (prefix[b + 1] - prefix[a]) / Double(b - a + 1)
        }
    }
}

public struct CursorPath {
    public static let rate = 120.0
    private let raw: [CursorLog.Sample]
    private let smoothed: [CGPoint]
    private let types: [CursorLog.TypeChange]
    private let activity: [Double]

    let detectedHovers: [Double]

    public init(log: CursorLog, duration: Double, pointSize: CGSize, hovers: [Double] = [],
                smoother: CursorSmoother = CursorSmoother()) {
        let raw = log.samples.filter { $0.t.isFinite && $0.x.isFinite && $0.y.isFinite }.sorted { $0.t < $1.t }
        self.raw = raw
        types = log.types.filter { $0.t.isFinite }.sorted { $0.t < $1.t }.reduce(into: []) { out, change in
            if out.last?.type != change.type { out.append(change) }
        }
        detectedHovers = hovers
        let hovers = (hovers + types.dropFirst().map(\.t)).filter { $0 >= 0 && $0 <= duration }.sorted()
        let n = Int((max(duration, 0) * Self.rate).rounded(.up)) + 1
        guard !raw.isEmpty else {
            smoothed = []
            activity = []
            return
        }
        var grid: [CGPoint] = []
        grid.reserveCapacity(n)
        var j = 0
        for i in 0 ..< n {
            let t = Double(i) / Self.rate
            while j + 1 < raw.count && raw[j + 1].t <= t { j += 1 }
            grid.append(Self.interpolate(raw, j, t))
        }
        let pins = log.clicks.filter { $0.t >= 0 && $0.t <= duration }.map { (t: $0.t, point: CGPoint(x: $0.x, y: $0.y)) }
        smoothed = smoother.smooth(grid, rate: Self.rate, pointSize: pointSize, pins: pins, hovers: hovers)
        activity = Self.activity(raw: raw, clicks: log.clicks, pointSize: pointSize)
    }

    static func activity(raw: [CursorLog.Sample], clicks: [CursorLog.Sample], pointSize: CGSize) -> [Double] {
        var out: [Double] = []
        var anchor: CursorLog.Sample?
        let w = pointSize.width > 0 ? pointSize.width : 1000, h = pointSize.height > 0 ? pointSize.height : 1000
        for s in raw {
            guard let a = anchor else {
                anchor = s
                continue
            }
            if hypot((s.x - a.x) * w, (s.y - a.y) * h) > 0.5 {
                out.append(s.t)
                anchor = s
            }
        }
        return (out + clicks.map(\.t).filter(\.isFinite)).sorted()
    }

    public func idleTime(at t: Double) -> Double {
        var lo = 0, hi = activity.count - 1
        guard hi >= 0, activity[0] <= t else { return max(t, 0) }
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if activity[mid] <= t { lo = mid } else { hi = mid - 1 }
        }
        return t - activity[lo]
    }

    public var isEmpty: Bool { raw.isEmpty }

    public func position(at t: Double, smooth: Bool) -> CGPoint? {
        guard !raw.isEmpty else { return nil }
        if smooth, !smoothed.isEmpty {
            let f = min(max(t, 0) * Self.rate, Double(smoothed.count - 1))
            let i = Int(f), k = min(i + 1, smoothed.count - 1)
            return CGPoint(x: lerp(smoothed[i].x, smoothed[k].x, f - Double(i)), y: lerp(smoothed[i].y, smoothed[k].y, f - Double(i)))
        }
        var lo = 0, hi = raw.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if raw[mid].t <= t { lo = mid } else { hi = mid - 1 }
        }
        return Self.interpolate(raw, lo, t)
    }

    public func type(at t: Double) -> CursorType {
        types.isEmpty ? .arrow : types[lastChange(atOrBefore: t)].type
    }

    public func stableType(at t: Double, settle: Double) -> (type: CursorType, since: Double, previous: CursorType?) {
        guard !types.isEmpty else { return (.arrow, -.infinity, nil) }
        func shown(_ k: Int) -> Int {
            var m = k
            while m > 0 && duration(m) < settle { m -= 1 }
            return m
        }
        let current = shown(lastChange(atOrBefore: t))
        let type = types[current].type
        var k = current
        while k > 0 {
            let before = shown(k - 1)
            if types[before].type != type { return (type, types[k].t, types[before].type) }
            k = before
        }
        return (type, -.infinity, nil)
    }

    private func duration(_ k: Int) -> Double { k + 1 < types.count ? types[k + 1].t - types[k].t : .infinity }

    private func lastChange(atOrBefore t: Double) -> Int {
        var lo = 0, hi = types.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if types[mid].t <= t { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }

    private static func interpolate(_ raw: [CursorLog.Sample], _ j: Int, _ t: Double) -> CGPoint {
        let a = raw[j]
        guard j + 1 < raw.count, a.t <= t else { return CGPoint(x: a.x, y: a.y) }
        let b = raw[j + 1]
        let f = (t - a.t) / max(b.t - a.t, 1e-6)
        return CGPoint(x: lerp(a.x, b.x, f), y: lerp(a.y, b.y, f))
    }
}

public struct CursorMotion {
    private var paths: [UUID: CursorPath] = [:]
    public private(set) var smoothing = CursorSettings().smoothing

    public init() {}

    public init(project: Project, logs: [UUID: CursorLog], reusing previous: CursorMotion? = nil) {
        smoothing = project.cursor.smoothing
        let reusable = previous?.smoothing == smoothing ? previous : nil
        let smoother = CursorSmoother(strength: smoothing)
        for clip in project.clips where clip.hasEditableCursor {
            guard let log = logs[clip.id] else { continue }
            let path = reusable?.paths[clip.id]
            if let path, path.detectedHovers == clip.hoverMoments ?? [] {
                paths[clip.id] = path
            } else {
                paths[clip.id] = CursorPath(log: log, duration: clip.duration, pointSize: clip.captureRect.size,
                                            hovers: clip.hoverMoments ?? [], smoother: smoother)
            }
        }
    }

    public func path(for clipID: UUID) -> CursorPath? { paths[clipID] }
}
