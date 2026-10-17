//
//  CursorTrack.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/9/26.
//

import CoreGraphics
import Foundation

public struct CursorTrack {
    public static let rate = 30.0
    private var points: [CGPoint]
    public private(set) var clicks: [(t: Double, point: CGPoint)]
    public private(set) var keys: [KeyPress]
    public private(set) var keyHits: [KeyHit]
    public let motion: CursorMotion

    public init(project: Project, logs: [UUID: CursorLog], smoothing tau: Double = 0.45, motion: CursorMotion? = nil) {
        self.motion = motion ?? CursorMotion(project: project, logs: logs)
        var raw: [(t: Double, p: CGPoint)] = []
        var clicks: [(Double, CGPoint)] = []
        var keys: [KeyPress] = []
        var hits: [KeyHit] = []
        for (i, clip) in project.clips.enumerated() {
            guard let log = logs[clip.id] else { continue }
            for s in log.samples where s.t >= 0 && s.t <= clip.duration {
                if let e = project.editedTime(clipIndex: i, local: s.t) { raw.append((e, CGPoint(x: s.x, y: s.y))) }
            }
            for c in log.clicks where c.t >= 0 && c.t <= clip.duration && (0...1).contains(c.x) && (0...1).contains(c.y) {
                if let e = project.editedTime(clipIndex: i, local: c.t) { clicks.append((e, CGPoint(x: c.x, y: c.y))) }
            }
            for k in log.keys where k.t >= 0 && k.t <= clip.duration {
                if let e = project.editedTime(clipIndex: i, local: k.t) { keys.append(KeyPress(t: e, modifiers: k.modifiers, key: k.key)) }
            }
            for h in log.keyHits where h.t >= 0 && h.t <= clip.duration {
                if let seg = project.segment(clipIndex: i, local: h.t), !seg.isSpedUp {
                    hits.append(KeyHit(t: seg.edited(local: h.t), kind: h.kind))
                }
            }
        }
        raw.sort { $0.t < $1.t }
        self.clicks = clicks.sorted { $0.0 < $1.0 }
        self.keys = keys.sorted { $0.t < $1.t }
        keyHits = hits.sorted { $0.t < $1.t }

        let n = Int((project.duration * Self.rate).rounded(.up)) + 1
        guard !raw.isEmpty, n > 0 else {
            points = []
            return
        }
        var resampled: [CGPoint] = []
        resampled.reserveCapacity(n)
        var j = 0
        for i in 0 ..< n {
            let t = Double(i) / Self.rate
            while j + 1 < raw.count && raw[j + 1].t <= t { j += 1 }
            var p = raw[j].p
            if j + 1 < raw.count, raw[j].t <= t {
                let a = raw[j], b = raw[j + 1]
                let f = (t - a.t) / max(b.t - a.t, 1e-6)
                p = CGPoint(x: lerp(a.p.x, b.p.x, f), y: lerp(a.p.y, b.p.y, f))
            }
            resampled.append(CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1)))
        }
        let alpha = 1 - exp(-1 / (Self.rate * tau))
        for i in 1 ..< resampled.count {
            resampled[i].x += (resampled[i - 1].x - resampled[i].x) * (1 - alpha)
            resampled[i].y += (resampled[i - 1].y - resampled[i].y) * (1 - alpha)
        }
        for i in stride(from: resampled.count - 2, through: 0, by: -1) {
            resampled[i].x += (resampled[i + 1].x - resampled[i].x) * (1 - alpha)
            resampled[i].y += (resampled[i + 1].y - resampled[i].y) * (1 - alpha)
        }
        points = resampled
    }

    public var isEmpty: Bool { points.isEmpty }

    public func position(at t: Double) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let f = max(t, 0) * Self.rate
        let i = min(Int(f), points.count - 1)
        let k = min(i + 1, points.count - 1)
        let frac = f - Double(i)
        return CGPoint(x: lerp(points[i].x, points[k].x, frac), y: lerp(points[i].y, points[k].y, frac))
    }
}

public enum AutoZoom {
    public static func suggest(clicks: [(t: Double, point: CGPoint)], duration: Double,
                               scale: Double = 2, maxGap: Double = 2.5, maxDistance: Double = 0.3) -> [ZoomBlock] {
        var clusters: [[(t: Double, point: CGPoint)]] = []
        for click in clicks.sorted(by: { $0.t < $1.t }) {
            if var last = clusters.last, let prev = last.last, click.t - prev.t <= maxGap,
               distance(centroid(last), click.point) <= maxDistance {
                last.append(click)
                clusters[clusters.count - 1] = last
            } else {
                clusters.append([click])
            }
        }
        var blocks: [ZoomBlock] = []
        for cluster in clusters {
            var start = max(cluster.first!.t - 0.8, 0)
            var end = min(max(cluster.last!.t + 1.8, start + 2.5), duration)
            if let prev = blocks.last, start < prev.end + 0.5 {
                start = prev.end
            }
            end = max(end, start)
            guard end - start >= 1 else { continue }
            blocks.append(ZoomBlock(start: start, end: end, scale: scale, focus: centroid(cluster), isAuto: true))
        }
        return blocks
    }

    private static func centroid(_ c: [(t: Double, point: CGPoint)]) -> CGPoint {
        let n = CGFloat(c.count)
        return CGPoint(x: c.reduce(0) { $0 + $1.point.x } / n, y: c.reduce(0) { $0 + $1.point.y } / n)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
}
