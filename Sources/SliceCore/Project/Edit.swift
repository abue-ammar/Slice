//
//  Edit.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/3/26.
//

import Foundation

public struct Cut: Codable, Equatable, Identifiable {
    public var id: UUID
    public var clipID: UUID
    public var start: Double
    public var end: Double

    public init(id: UUID = UUID(), clipID: UUID, start: Double, end: Double) {
        self.id = id
        self.clipID = clipID
        self.start = start
        self.end = end
    }
}

public struct Split: Codable, Equatable {
    public var clipID: UUID
    public var time: Double
    public init(clipID: UUID, time: Double) {
        self.clipID = clipID
        self.time = time
    }
}

public struct Segment: Equatable {
    public var clipIndex: Int
    public var sourceStart: Double
    public var sourceEnd: Double
    public var editedStart: Double
    public var speed = 1.0
    public var sourceDuration: Double { sourceEnd - sourceStart }
    /// How long it plays for in the edit.
    public var duration: Double { sourceDuration / speed }
    public var editedEnd: Double { editedStart + duration }
    public var isSpedUp: Bool { speed > 1 + 1e-6 }
    public var isSlowed: Bool { speed < 1 - 1e-6 }
    /// Any speed but 1× plays without sound.
    public var isRetimed: Bool { abs(speed - 1) > 1e-6 }

    public func local(at t: Double) -> Double { sourceStart + min(max(t - editedStart, 0) * speed, sourceDuration) }
    public func edited(local: Double) -> Double { editedStart + (local - sourceStart) / speed }
}

extension Project {
    static let minSegment = 1.0 / 60

    func cuts(forClip id: UUID, duration: Double) -> [(Double, Double)] {
        let ranges = cuts.filter { $0.clipID == id }
            .map { (max($0.start, 0), min($0.end, duration)) }
            .filter { $0.1 > $0.0 }
            .sorted { $0.0 < $1.0 }
        var merged: [(Double, Double)] = []
        for r in ranges {
            if let last = merged.last, r.0 <= last.1 {
                merged[merged.count - 1].1 = max(last.1, r.1)
            } else {
                merged.append(r)
            }
        }
        return merged
    }

    public var segments: [Segment] {
        var out: [Segment] = []
        var t = 0.0
        for (i, clip) in clips.enumerated() {
            let ranges = speedRanges(forClip: clip.id)
            let marks = (splits.filter { $0.clipID == clip.id }.map(\.time) + ranges.flatMap { [$0.start, $0.end] }).sorted()
            var cursor = 0.0
            func add(_ a: Double, _ b: Double) {
                let mid = (a + b) / 2
                let speed = ranges.first { $0.start <= mid && mid < $0.end }?.speed ?? 1
                let seg = Segment(clipIndex: i, sourceStart: a, sourceEnd: b, editedStart: t, speed: speed)
                out.append(seg)
                t = seg.editedEnd
            }
            for (a, b) in cuts(forClip: clip.id, duration: clip.duration) + [(clip.duration, clip.duration)] {
                var pieceStart = cursor
                for s in marks where s > pieceStart + Self.minSegment && s < a - Self.minSegment {
                    add(pieceStart, s)
                    pieceStart = s
                }
                if a - pieceStart >= Self.minSegment { add(pieceStart, a) }
                cursor = max(cursor, b)
            }
        }
        return out
    }

    public static let minSplitMargin = 0.05

    public func canSplit(at t: Double) -> Bool {
        guard let (ci, local) = sourceTime(edited: t) else { return false }
        return segments.contains {
            $0.clipIndex == ci && local > $0.sourceStart + Self.minSplitMargin && local < $0.sourceEnd - Self.minSplitMargin
        }
    }

    @discardableResult
    public mutating func split(at t: Double) -> Bool {
        guard canSplit(at: t), let (ci, local) = sourceTime(edited: t) else { return false }
        splits.append(Split(clipID: clips[ci].id, time: local))
        return true
    }

    public mutating func trim(segment seg: Segment, newStart: Double? = nil, newEnd: Double? = nil) {
        let ci = seg.clipIndex, id = clips[ci].id
        if let ns = newStart {
            let s = min(max(ns, 0), seg.sourceEnd - 0.1)
            if s > seg.sourceStart { removeSource(clipIndex: ci, from: seg.sourceStart, to: s) } else if s < seg.sourceStart { restore(clipID: id, from: s, to: seg.sourceStart) }
            for i in transitions.indices where transitions[i].clipID == id && abs(transitions[i].time - seg.sourceStart) < 1e-3 {
                transitions[i].time = s
            }
        }
        if let ne = newEnd {
            let start = newStart.map { min(max($0, 0), seg.sourceEnd - 0.1) } ?? seg.sourceStart
            let e = max(min(ne, clips[ci].duration), start + 0.1)
            if e < seg.sourceEnd { removeSource(clipIndex: ci, from: e, to: seg.sourceEnd) } else if e > seg.sourceEnd { restore(clipID: id, from: seg.sourceEnd, to: e) }
        }
    }

    public mutating func delete(segment seg: Segment) {
        removeTime(from: seg.editedStart, to: seg.editedEnd)
    }

    public var duration: Double { segments.last?.editedEnd ?? 0 }

    public var clipStarts: [Double] {
        let segs = segments
        var starts = [Double](repeating: 0, count: clips.count)
        var next = duration
        for i in clips.indices.reversed() {
            if let first = segs.first(where: { $0.clipIndex == i }) { next = first.editedStart }
            starts[i] = next
        }
        return starts
    }

    public var clipEditedDurations: [Double] {
        let segs = segments
        return clips.indices.map { i in segs.filter { $0.clipIndex == i }.reduce(0) { $0 + $1.duration } }
    }

    public func editedTime(clipIndex: Int, local: Double) -> Double? {
        segment(clipIndex: clipIndex, local: local)?.edited(local: local)
    }

    public func segment(clipIndex: Int, local: Double) -> Segment? {
        segments.first { $0.clipIndex == clipIndex && local >= $0.sourceStart && local <= $0.sourceEnd }
    }

    public func editedPosition(clipIndex: Int, local: Double) -> Double {
        if let e = editedTime(clipIndex: clipIndex, local: local) { return e }
        let segs = segments
        if let next = segs.first(where: { ($0.clipIndex == clipIndex && $0.sourceStart >= local) || $0.clipIndex > clipIndex }) {
            return next.editedStart
        }
        return duration
    }

    public func sourceTime(edited t: Double) -> (clipIndex: Int, local: Double)? {
        let segs = segments
        guard let s = segs.last(where: { $0.editedStart <= t }) ?? segs.first else { return nil }
        return (s.clipIndex, s.local(at: t))
    }

    public mutating func removeTime(from a: Double, to b: Double) {
        let a = max(a, 0), b = min(b, duration)
        guard b - a > 1e-6 else { return }
        for s in segments where s.editedEnd > a && s.editedStart < b {
            let lo = s.local(at: a)
            let hi = s.local(at: b)
            cuts.append(Cut(clipID: clips[s.clipIndex].id, start: lo, end: hi))
        }
        normaliseCuts()
        let len = b - a
        func remap(_ start: Double, _ end: Double) -> (Double, Double)? {
            if end <= a { return (start, end) }
            if start >= b { return (start - len, end - len) }
            let ns = start < a ? start : a
            let ne = end > b ? end - len : a
            return ne - ns >= 0.1 ? (ns, ne) : nil
        }
        cameraBlocks = cameraBlocks.compactMap { blk in remap(blk.start, blk.end).map { var blk = blk; (blk.start, blk.end) = $0; return blk } }
        zoomBlocks = zoomBlocks.compactMap { blk in remap(blk.start, blk.end).map { var blk = blk; (blk.start, blk.end) = $0; return blk } }
        redactions = redactions.compactMap { blk in remap(blk.start, blk.end).map { var blk = blk; (blk.start, blk.end) = $0; return blk } }
        spotlights = spotlights.compactMap { blk in remap(blk.start, blk.end).map { var blk = blk; (blk.start, blk.end) = $0; return blk } }
        annotations = annotations.compactMap { blk in remap(blk.start, blk.end).map { var blk = blk; (blk.start, blk.end) = $0; return blk } }
    }

    public mutating func removeSource(clipIndex: Int, from a: Double, to b: Double) {
        let ea = editedPosition(clipIndex: clipIndex, local: a)
        let eb = editedPosition(clipIndex: clipIndex, local: b)
        removeTime(from: ea, to: eb)
    }

    public mutating func restore(clipID: UUID, from a: Double, to b: Double) {
        guard let ci = clips.firstIndex(where: { $0.id == clipID }) else { return }
        let before = duration
        let join = editedPosition(clipIndex: ci, local: a)
        var kept: [Cut] = []
        for c in cuts {
            guard c.clipID == clipID, c.end > a, c.start < b else {
                kept.append(c)
                continue
            }
            if c.start < a { kept.append(Cut(clipID: clipID, start: c.start, end: a)) }
            if c.end > b { kept.append(Cut(clipID: clipID, start: b, end: c.end)) }
        }
        cuts = kept
        let len = duration - before
        guard len > 1e-6 else { return }
        func remap(_ start: Double, _ end: Double) -> (Double, Double) {
            if start >= join { return (start + len, end + len) }
            if end > join { return (start, end + len) }
            return (start, end)
        }
        for i in cameraBlocks.indices { (cameraBlocks[i].start, cameraBlocks[i].end) = remap(cameraBlocks[i].start, cameraBlocks[i].end) }
        for i in zoomBlocks.indices { (zoomBlocks[i].start, zoomBlocks[i].end) = remap(zoomBlocks[i].start, zoomBlocks[i].end) }
        for i in redactions.indices { (redactions[i].start, redactions[i].end) = remap(redactions[i].start, redactions[i].end) }
        for i in spotlights.indices { (spotlights[i].start, spotlights[i].end) = remap(spotlights[i].start, spotlights[i].end) }
        for i in annotations.indices { (annotations[i].start, annotations[i].end) = remap(annotations[i].start, annotations[i].end) }
    }

    mutating func normaliseCuts() {
        var out: [Cut] = []
        for clip in clips {
            for (a, b) in cuts(forClip: clip.id, duration: clip.duration) {
                out.append(Cut(clipID: clip.id, start: a, end: b))
            }
        }
        cuts = out
    }

    public func isCut(clipID: UUID, local: Double) -> Bool {
        cuts.contains { $0.clipID == clipID && local >= $0.start && local < $0.end }
    }

    public var joins: [Join] {
        let segs = segments
        var out: [Join] = []
        func whole(_ range: Range<Int>) -> [Join.Gap] {
            range.map { Join.Gap(clipID: clips[$0].id, start: 0, end: clips[$0].duration) }
        }
        func head(_ s: Segment) -> [Join.Gap] {
            s.sourceStart > 1e-6 ? [Join.Gap(clipID: clips[s.clipIndex].id, start: 0, end: s.sourceStart)] : []
        }
        func tail(_ s: Segment) -> [Join.Gap] {
            let d = clips[s.clipIndex].duration
            return d - s.sourceEnd > 1e-6 ? [Join.Gap(clipID: clips[s.clipIndex].id, start: s.sourceEnd, end: d)] : []
        }
        for (i, seg) in segs.enumerated() {
            guard i > 0 else {
                let gaps = whole(0 ..< seg.clipIndex) + head(seg)
                if !gaps.isEmpty { out.append(Join(time: 0, previous: nil, next: seg, gaps: gaps)) }
                continue
            }
            let prev = segs[i - 1]
            if prev.clipIndex == seg.clipIndex {
                let gaps = seg.sourceStart - prev.sourceEnd > 1e-6
                    ? [Join.Gap(clipID: clips[seg.clipIndex].id, start: prev.sourceEnd, end: seg.sourceStart)] : []
                out.append(Join(time: seg.editedStart, previous: prev, next: seg, gaps: gaps))
            } else {
                let gaps = tail(prev) + whole(prev.clipIndex + 1 ..< seg.clipIndex) + head(seg)
                if !gaps.isEmpty { out.append(Join(time: seg.editedStart, previous: prev, next: seg, gaps: gaps)) }
            }
        }
        if let last = segs.last {
            let gaps = tail(last) + whole(last.clipIndex + 1 ..< clips.count)
            if !gaps.isEmpty { out.append(Join(time: last.editedEnd, previous: last, next: nil, gaps: gaps)) }
        }
        return out
    }

    public mutating func heal(_ join: Join) {
        if join.gaps.isEmpty, let prev = join.previous, let next = join.next, prev.clipIndex == next.clipIndex {
            let id = clips[prev.clipIndex].id
            splits.removeAll { $0.clipID == id && abs($0.time - next.sourceStart) < 1e-6 }
            if abs(prev.speed - next.speed) > 1e-6 { setSpeed(prev.speed, for: next) }
            return
        }
        for gap in join.gaps { restore(clipID: gap.clipID, from: gap.start, to: gap.end) }
    }
}

public struct Join: Equatable {
    public struct Gap: Equatable {
        public var clipID: UUID
        public var start: Double
        public var end: Double
    }

    public var time: Double
    public var previous: Segment?
    public var next: Segment?
    public var gaps: [Gap]

    public var removed: Double { gaps.reduce(0) { $0 + $1.end - $1.start } }
}

extension Project {
    public mutating func removeWords(clipIndex: Int, words: [Word], first: Int, last: Int) {
        guard words.indices.contains(first), words.indices.contains(last), first <= last else { return }
        let prevEnd = first > 0 ? words[first - 1].end : 0
        let start = max(words[first].start - 0.03, (prevEnd + words[first].start) / 2)
        var end: Double
        if last + 1 < words.count {
            let next = words[last + 1]
            end = next.start - words[last].end < 1.0 ? next.start - 0.03 : words[last].end + 0.25
        } else {
            end = min(words[last].end + 0.12, clips[clipIndex].duration)
        }
        removeSource(clipIndex: clipIndex, from: start, to: max(end, start))
    }
}
