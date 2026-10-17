//
//  QuietMoments.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import Foundation

/// Finds the stretches of a take worth speeding up: idle ones, where nothing moves, nobody clicks, types or speaks;
/// and typing ones, where someone just types for a while without talking.
public enum QuietMoments {
    public struct Settings: Equatable, Sendable {
        public var idle = true
        public var typing = true
        public var idleSpeed = 4.0
        public var typingSpeed = 2.0
        public init() {}
    }

    static let bin = 0.25
    static let minIdle = 2.0
    static let minTyping = 3.0
    /// Kept at normal speed on each side, so what happens just before and after still reads.
    static let margin = 0.4
    static let typingGap = 1.0
    static let moving = 0.004

    public static func find(project: Project, logs: [UUID: CursorLog], settings: Settings) -> [SpeedRange] {
        project.clips.flatMap { clip -> [SpeedRange] in
            guard let log = logs[clip.id], clip.duration > minIdle else { return [] }
            var out: [SpeedRange] = []
            let speech = clip.speech ?? []
            if settings.idle {
                out += idleSpans(log: log, speech: speech, duration: clip.duration)
                    .map { SpeedRange(clipID: clip.id, start: $0.start, end: $0.end, speed: settings.idleSpeed, isAuto: true) }
            }
            if settings.typing {
                out += typingSpans(log: log, speech: speech, duration: clip.duration)
                    .map { SpeedRange(clipID: clip.id, start: $0.start, end: $0.end, speed: settings.typingSpeed, isAuto: true) }
            }
            return out.sorted { $0.start < $1.start }
        }
    }

    static func idleSpans(log: CursorLog, speech: [TimeSpan], duration: Double) -> [TimeSpan] {
        let n = Int((duration / bin).rounded(.up))
        guard n > 0 else { return [] }
        var busy = [Bool](repeating: false, count: n)
        func mark(_ a: Double, _ b: Double) {
            let lo = max(Int((a / bin).rounded(.down)), 0), hi = min(Int((b / bin).rounded(.down)), n - 1)
            if lo <= hi { for i in lo ... hi { busy[i] = true } }
        }
        for s in speech { mark(s.start, s.end) }
        for c in log.clicks { mark(c.t - 0.6, c.t + 0.6) }
        for s in log.scrolls { mark(s.t - 0.4, s.t + 0.4) }
        for h in log.keyHits { mark(h.t - 0.3, h.t + 0.3) }
        var travel = [Double](repeating: 0, count: n)
        for (a, b) in zip(log.samples, log.samples.dropFirst()) {
            let i = Int((b.t / bin).rounded(.down))
            guard i >= 0, i < n else { continue }
            travel[i] += hypot(b.x - a.x, b.y - a.y)
        }
        for i in 0 ..< n where travel[i] > moving { busy[i] = true }

        var out: [TimeSpan] = []
        var i = 0
        while i < n {
            guard !busy[i] else { i += 1; continue }
            var j = i
            while j < n, !busy[j] { j += 1 }
            let a = Double(i) * bin, b = min(Double(j) * bin, duration)
            if b - a >= minIdle {
                let span = TimeSpan(start: a + (a > 0 ? margin : 0), end: b - (b < duration ? margin : 0))
                if span.end - span.start >= 1 { out.append(span) }
            }
            i = j
        }
        return out
    }

    static func typingSpans(log: CursorLog, speech: [TimeSpan], duration: Double) -> [TimeSpan] {
        let hits = log.keyHits.map(\.t).filter { $0 >= 0 && $0 <= duration }.sorted()
        guard var first = hits.first else { return [] }
        var runs: [TimeSpan] = []
        var last = first
        for t in hits.dropFirst() {
            if t - last > typingGap {
                runs.append(TimeSpan(start: first, end: last))
                first = t
            }
            last = t
        }
        runs.append(TimeSpan(start: first, end: last))
        return runs.compactMap { run in
            guard run.end - run.start >= minTyping else { return nil }
            let span = TimeSpan(start: run.start + margin, end: run.end - margin)
            guard !speech.contains(where: { $0.end > span.start && $0.start < span.end }),
                  !log.clicks.contains(where: { $0.t > span.start && $0.t < span.end }) else { return nil }
            return span
        }
    }
}
