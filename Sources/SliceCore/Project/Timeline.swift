//
//  Timeline.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/12/26.
//

import Foundation

public protocol Interpolatable {
    static func interpolate(_ a: Self, _ b: Self, _ t: Double) -> Self
}

public enum Easing {
    public static func inOut(_ x: Double) -> Double { EasingCurve.smooth(x) }
}

public struct SegmentTimeline<Value: Interpolatable> {
    public struct Segment {
        public var start: Double
        public var end: Double
        public var key: AnyHashable
        public var value: (Double) -> Value
        public var transition: Double
        public var easing: (Double) -> Double
    }

    public typealias Block = (start: Double, end: Double, key: AnyHashable, value: (Double) -> Value)

    public private(set) var segments: [Segment]
    public var transition: Double

    public init(blocks: [Block], gapKey: AnyHashable, gap: @escaping (Double) -> Value, duration: Double, transition: Double) {
        self.init(blocks: blocks.map { ($0, nil, nil) }, gapKey: gapKey, gap: gap, duration: duration, transition: transition)
    }

    public init(blocks: [(block: Block, transition: Double?, easing: ((Double) -> Double)?)], gapKey: AnyHashable,
                gap: @escaping (Double) -> Value, duration: Double, transition: Double) {
        self.transition = transition
        var out: [Segment] = []
        var cursor = 0.0
        var leaving: (Double, (Double) -> Double) = (transition, Easing.inOut)
        let sorted = blocks.filter { $0.block.end > $0.block.start }.sorted { $0.block.start < $1.block.start }
        for (i, entry) in sorted.enumerated() {
            let b = entry.block
            let start = max(b.start, cursor)
            let nextStart = i + 1 < sorted.count ? sorted[i + 1].block.start : .infinity
            let end = min(b.end, nextStart, max(duration, start))
            guard end > start else { continue }
            if start > cursor {
                out.append(Segment(start: cursor, end: start, key: gapKey, value: gap, transition: leaving.0, easing: leaving.1))
            }
            let own = (max(entry.transition ?? transition, 0), entry.easing ?? Easing.inOut)
            out.append(Segment(start: start, end: end, key: b.key, value: b.value, transition: own.0, easing: own.1))
            leaving = own
            cursor = end
        }
        if cursor < duration || out.isEmpty {
            out.append(Segment(start: cursor, end: max(duration, cursor), key: gapKey, value: gap, transition: leaving.0,
                               easing: leaving.1))
        }
        segments = out
    }

    public func segmentIndex(at t: Double) -> Int {
        segments.lastIndex { $0.start <= t } ?? 0
    }

    public func value(at t: Double) -> Value {
        value(index: segmentIndex(at: t), t: t)
    }

    private func value(index i: Int, t: Double) -> Value {
        let seg = segments[i]
        let target = seg.value(t)
        guard i > 0, seg.transition > 0, segments[i - 1].key != seg.key else { return target }
        let progress = (t - seg.start) / seg.transition
        guard progress < 1 else { return target }
        let from = value(index: i - 1, t: t)
        return Value.interpolate(from, target, seg.easing(progress))
    }
}
