//
//  SmartZoom.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/10/26.
//

import AVFoundation
import CoreGraphics
import Foundation

public struct AutoZoomSettings: Codable, Equatable {
    public var intensity = 0.5
    public var selectivity = 0.5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AutoZoomSettings()
        intensity = try c.decodeIfPresent(Double.self, forKey: .intensity) ?? d.intensity
        selectivity = try c.decodeIfPresent(Double.self, forKey: .selectivity) ?? d.selectivity
    }

    public var targetScale: Double { 1.5 + min(max(intensity, 0), 1) * 1.2 }
    var threshold: Double { 0.45 + min(max(selectivity, 0), 1) * 0.25 }
}

public enum SmartZoom {
    public struct Moment: Equatable, Sendable {
        public enum Kind: String, Sendable { case click, pause, typing }
        public var kind: Kind
        public var t: Double
        public var end: Double
        public var point: CGPoint
        public var score: Double
        public var response: CGRect?
        public var pageChange = false
        public var typing = false
        /// When typing after this moment began.
        public var typingStart: Double?
        /// Where the typed text showed up on screen.
        public var typed: CGRect?
    }

    public struct Detection: Equatable, Sendable {
        public var moments: [Moment]
        public var scrolls: [TimeSpan]
    }

    // MARK: - Detect

    public static func detect(project: Project, logs: [UUID: CursorLog], bundle: ProjectBundle, only: Set<UUID>? = nil,
                              progress: @escaping @Sendable (Double) -> Void = { _ in }) async -> [UUID: Detection] {
        let todo = project.clips.filter { (only?.contains($0.id) ?? true) && logs[$0.id] != nil }
        var out: [UUID: Detection] = [:]
        for (k, clip) in todo.enumerated() {
            guard let log = logs[clip.id], !Task.isCancelled else { continue }
            var detection = interactions(log: log, pointSize: pointSize(of: clip), duration: clip.duration)
            let clicks = detection.moments.indices.filter { detection.moments[$0].kind == .click }
            // Takes recorded in Slice measured their clicks while recording; only the rest decode the video.
            let cached = ScreenChange.cached(at: bundle.screenChangesURL(for: clip))
            var missing: [Int] = []
            for i in clicks {
                if let change = ScreenChange.lookup(cached, t: detection.moments[i].t, point: detection.moments[i].point) {
                    apply(change, to: &detection.moments[i])
                } else {
                    missing.append(i)
                }
            }
            if !missing.isEmpty {
                let changes = await ScreenChange.measure(
                    video: bundle.file(clip.screenFile), clicks: missing.map { (detection.moments[$0].t, detection.moments[$0].point) },
                    duration: clip.duration) { p in progress((Double(k) + p) / Double(todo.count)) }
                for (i, change) in zip(missing, changes) { if let change { apply(change, to: &detection.moments[i]) } }
            }
            await measureTyping(&detection, video: bundle.file(clip.screenFile), duration: clip.duration) { p in
                progress((Double(k) + p) / Double(todo.count))
            }
            out[clip.id] = detection
            progress(Double(k + 1) / Double(todo.count))
        }
        return out
    }

    static func pointSize(of clip: Clip) -> CGSize {
        if clip.captureRect.width > 0, clip.captureRect.height > 0 { return clip.captureRect.size }
        return CGSize(width: max(clip.screenPixelSize.width / 2, 1), height: max(clip.screenPixelSize.height / 2, 1))
    }

    static func interactions(log: CursorLog, pointSize: CGSize, duration: Double) -> Detection {
        let samples = log.samples.filter { $0.t.isFinite && $0.x.isFinite && $0.y.isFinite }.sorted { $0.t < $1.t }
        let scrolls = bursts(log.scrolls.map(\.t).filter { $0 >= 0 && $0 <= duration }.sorted(), gap: 0.5, tail: 0.3)
        let typing = bursts(log.typing.filter { $0 >= 0 && $0 <= duration }.sorted(), gap: 1.2, tail: typingTail)
        guard samples.count > 1, duration > 0 else { return Detection(moments: [], scrolls: scrolls) }

        let rate = 60.0
        let n = Int(duration * rate) + 1
        let path = (0 ..< n).map { HoverDetector.position(in: samples, at: Double($0) / rate) }
        var speed = [Double](repeating: 0, count: n)
        for i in 0 ..< n {
            let a = path[max(i - 1, 0)], b = path[min(i + 1, n - 1)]
            let span = Double(min(i + 1, n - 1) - max(i - 1, 0)) / rate
            speed[i] = span > 0 ? hypot((b.x - a.x) * pointSize.width, (b.y - a.y) * pointSize.height) / span : 0
        }
        func index(_ t: Double) -> Int { min(max(Int((t * rate).rounded()), 0), n - 1) }
        func speeds(_ a: Double, _ b: Double) -> ArraySlice<Double> {
            let i = index(a), j = index(b)
            return i <= j ? speed[i ... j] : []
        }
        func points(_ p: CGPoint, _ q: CGPoint) -> Double {
            hypot((p.x - q.x) * pointSize.width, (p.y - q.y) * pointSize.height)
        }
        func overlaps(_ spans: [TimeSpan], _ a: Double, _ b: Double) -> Bool { spans.contains { $0.end > a && $0.start < b } }

        var moments: [Moment] = []
        var clicks: [(t: Double, point: CGPoint, double: Bool)] = []
        for c in log.clicks.sorted(by: { $0.t < $1.t })
        where c.t >= 0 && c.t <= duration && (0 ... 1).contains(c.x) && (0 ... 1).contains(c.y) {
            let p = CGPoint(x: c.x, y: c.y)
            if let last = clicks.last, c.t - last.t < 0.45, points(last.point, p) < 8 {
                clicks[clicks.count - 1].double = true
            } else {
                clicks.append((c.t, p, false))
            }
        }
        for c in clicks {
            let final = speeds(c.t - 0.2, c.t - 0.03)
            let finalSpeed = final.isEmpty ? 0 : final.reduce(0, +) / Double(final.count)
            let peak = speeds(c.t - 1.2, c.t - 0.25).max() ?? 0
            var dwell = 0.0
            while dwell < 2, points(path[index(c.t - dwell - 1 / rate)], c.point) < 10, c.t - dwell > 0 { dwell += 1 / rate }
            var precision = 0.6 * clamp(1 - finalSpeed / 500) + 0.4 * clamp(dwell / 0.4)
            if peak > 300, finalSpeed < peak * 0.25 { precision += 0.15 }
            var m = Moment(kind: .click, t: c.t, end: c.t, point: c.point, score: 0.35 + 0.4 * precision)
            if finalSpeed > 900 { m.score -= 0.35 }
            if overlaps(scrolls, c.t - 0.6, c.t + 0.3) { m.score -= 0.3 }
            if c.double { m.score += 0.05 }
            if let burst = typing.first(where: { $0.start > c.t + 0.03 && $0.start < c.t + 2.5 }) {
                m.typing = true
                m.typingStart = burst.start
                m.end = burst.end
                m.score += 0.3
            }
            moments.append(m)
        }
        for burst in typing where burst.end - burst.start >= minLoneTyping
            && !moments.contains(where: { $0.typingStart == burst.start }) {
            let length = burst.end - burst.start
            var m = Moment(kind: .typing, t: burst.start, end: burst.end, point: path[index(burst.start)],
                           score: 0.45 + 0.1 * min((length - minLoneTyping) / 2, 1))
            m.typing = true
            m.typingStart = burst.start
            if overlaps(scrolls, burst.start, burst.end) { m.score -= 0.2 }
            moments.append(m)
        }

        var i = 0
        while i < n {
            guard speed[i] < 25 else {
                i += 1
                continue
            }
            var j = i
            while j + 1 < n, speed[j + 1] < 25 { j += 1 }
            let a = Double(i) / rate, b = Double(j) / rate
            let p = path[i]
            if b - a >= 1, a > 0.5, (0 ... 1).contains(p.x), (0 ... 1).contains(p.y),
               points(path[index(a - 1.5)], p) >= 120,
               !clicks.contains(where: { $0.t > a - 0.3 && $0.t < b + 0.2 }),
               !overlaps(scrolls, a, b), !overlaps(typing, a, b) {
                let score = 0.3 + 0.12 * min(b - a - 1, 1.5) + ((speeds(a - 1.5, a).max() ?? 0) > 400 ? 0.08 : 0)
                moments.append(Moment(kind: .pause, t: a, end: b, point: p, score: score))
            }
            i = j + 1
        }
        return Detection(moments: moments.sorted { $0.t < $1.t }, scrolls: scrolls)
    }

    static let typingTail = 0.2

    static func bursts(_ times: [Double], gap: Double, tail: Double) -> [TimeSpan] {
        var out: [TimeSpan] = []
        for t in times {
            if let last = out.last, t - (last.end - tail) <= gap { out[out.count - 1].end = t + tail } else { out.append(TimeSpan(start: t, end: t + tail)) }
        }
        return out
    }

    static func apply(_ change: ScreenChange.Result, to m: inout Moment) {
        if change.fraction > 0.4 {
            m.pageChange = true
            m.score -= 0.05
        } else if let r = change.local {
            m.response = r
            m.score += 0.2
        } else if change.fraction < 0.0015 {
            m.score -= 0.1
        }
    }

    // MARK: - Plan

    static let minScale = 1.25
    static let minVisiblePoints = CGSize(width: 560, height: 340)
    static let margin = 0.06

    public static func plan(project: Project, detections: [UUID: Detection], settings: AutoZoomSettings) -> [ZoomBlock] {
        let transition = max(project.style.zoomTransitionDuration, 0.2)
        let duration = project.duration
        struct Placed { var m: Moment; var t: Double; var end: Double; var clip: Int }
        var placed: [Placed] = []
        var scrolls: [TimeSpan] = []
        for (ci, clip) in project.clips.enumerated() {
            guard let d = detections[clip.id] else { continue }
            for m in d.moments where m.score >= settings.threshold {
                guard let t = project.editedTime(clipIndex: ci, local: m.t) else { continue }
                let end = project.editedTime(clipIndex: ci, local: m.end) ?? t
                placed.append(Placed(m: m, t: t, end: max(end, t), clip: ci))
            }
            for s in d.scrolls {
                guard let a = project.editedTime(clipIndex: ci, local: s.start) else { continue }
                scrolls.append(TimeSpan(start: a, end: project.editedTime(clipIndex: ci, local: s.end) ?? a + s.end - s.start))
            }
        }
        placed.sort { $0.t < $1.t }

        let maxGap = max(2.2, 2 * transition + 0.4)
        var groups: [[Placed]] = []
        for p in placed {
            if let last = groups.last?.last, last.clip == p.clip, p.t - last.end <= maxGap, !last.m.pageChange,
               !scrolls.contains(where: { $0.end > last.end && $0.start < p.t }) {
                groups[groups.count - 1].append(p)
            } else {
                groups.append([p])
            }
        }

        var planned: [(block: ZoomBlock, core: ClosedRange<Double>)] = []
        for group in groups {
            let clip = project.clips[group[0].clip]
            let g = ScreenGeometry(contentSize: clip.screenPixelSize, output: project.outputSize(shortSide: 1080), style: project.style,
                                   shapedByAlpha: clip.device != nil)
            let size = pointSize(of: clip)
            let limit = min(settings.targetScale, pointLimit(g, points: size))
            guard limit >= minScale else { continue }
            var chunks: [[Placed]] = []
            for p in group {
                if let chunk = chunks.last, fit(box(chunk.map(\.m) + [p.m]), g) >= max(minScale, limit * 0.75) {
                    chunks[chunks.count - 1].append(p)
                } else {
                    chunks.append([p])
                }
            }
            var start = chunks[0][0].t - transition - 0.35
            for (k, chunk) in chunks.enumerated() {
                let first = chunk[0], last = chunk[chunk.count - 1]
                var end: Double
                if k + 1 < chunks.count {
                    let next = chunks[k + 1][0]
                    end = min(max(last.end + 0.25, next.t - transition * 0.9 - 0.1), next.t - 0.1)
                    end = max(end, last.t + 0.1)
                } else {
                    end = last.end + (last.m.pageChange ? 0.35 : last.m.typing ? 0.9 : 1.5)
                    end = max(end, chunks[0][0].t - transition - 0.35 + 2 * transition + 0.8)
                }
                let frame = box(chunk.map(\.m))
                var block = ZoomBlock(start: start, end: end, scale: min(limit, fit(frame, g)),
                                      focus: CGPoint(x: frame.midX, y: frame.midY), isAuto: true)
                block.easing = .smooth
                let typed = chunk.compactMap(\.m.typed).reduce(CGRect.null) { $0.union($1) }
                if !typed.isNull, block.scale < max(minScale, limit * 0.75), let pan = follow(typed, limit: limit, g) {
                    block.scale = pan.scale
                    block.focus = pan.from
                    block.endFocus = pan.to
                }
                planned.append((block, first.t ... max(last.end, first.t)))
                start = end
            }
        }

        planned.sort { $0.block.start < $1.block.start }
        var i = 1
        while i < planned.count {
            let prev = planned[i - 1], next = planned[i]
            if next.block.start - prev.block.end < transition + 0.6 {
                var b = max(prev.core.upperBound + 0.15, next.block.start)
                b = min(b, next.core.lowerBound - 0.1)
                if b <= prev.core.upperBound { b = (prev.core.upperBound + next.core.lowerBound) / 2 }
                planned[i - 1].block.end = b
                planned[i].block.start = b
            }
            i += 1
        }
        return planned.map(\.block).compactMap { b in
            var b = b
            b.start = max(b.start, 0)
            b.end = min(b.end, duration)
            return b.end - b.start >= 0.8 ? b : nil
        }
    }

    static func box(_ moments: [Moment]) -> CGRect {
        var r = CGRect.null
        for m in moments {
            r = r.union(CGRect(origin: m.point, size: .zero))
            if let resp = m.response { r = r.union(resp) }
            if let typed = m.typed { r = r.union(typed) }
        }
        r = r.insetBy(dx: -margin, dy: -margin)
        let w = max(r.width, 0.12), h = max(r.height, 0.12)
        return CGRect(x: r.midX - w / 2, y: r.midY - h / 2, width: w, height: h)
    }

    static func fit(_ box: CGRect, _ g: ScreenGeometry) -> Double {
        let c = g.contentRect.size
        guard c.width > 0, c.height > 0, box.width > 0, box.height > 0 else { return 1 }
        return min(g.fullBleedSize.width / (c.width * box.width), g.fullBleedSize.height / (c.height * box.height))
    }

    static func pointLimit(_ g: ScreenGeometry, points: CGSize) -> Double {
        let c = g.contentRect.size
        guard c.width > 0, c.height > 0 else { return 1 }
        return min(g.fullBleedSize.width / c.width * points.width / minVisiblePoints.width,
                   g.fullBleedSize.height / c.height * points.height / minVisiblePoints.height)
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}
