//
//  SpeedModel.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import Foundation

/// A stretch of a take that plays faster, in the take's own time (like a cut), so trimming and cutting around it
/// leave it where it is.
public struct SpeedRange: Codable, Equatable {
    public var clipID: UUID
    public var start: Double
    public var end: Double
    public var speed: Double
    /// Found by "Speed up quiet moments"; running it again replaces these and keeps the rest.
    public var isAuto: Bool

    public init(clipID: UUID, start: Double, end: Double, speed: Double, isAuto: Bool = false) {
        self.clipID = clipID
        self.start = start
        self.end = end
        self.speed = speed
        self.isAuto = isAuto
    }

    public static let choices: [Double] = [1, 2, 4, 8]

    public static func label(_ speed: Double) -> String {
        speed.rounded() == speed ? "\(Int(speed))×" : String(format: "%.1f×", speed)
    }
}

extension Project {
    func speedRanges(forClip id: UUID) -> [SpeedRange] {
        speeds.filter { $0.clipID == id && $0.end > $0.start && $0.speed > 0 }.sorted { $0.start < $1.start }
    }

    public var hasSpeedChanges: Bool { speeds.contains { abs($0.speed - 1) > 1e-6 } }

    /// Plays one section at `speed`. Blocks on the timeline keep to the moments they cover.
    public mutating func setSpeed(_ speed: Double, for seg: Segment) {
        guard clips.indices.contains(seg.clipIndex) else { return }
        let old = self
        replaceSpeed(speed, clipID: clips[seg.clipIndex].id, from: seg.sourceStart, to: seg.sourceEnd, isAuto: false)
        retime(from: old)
    }

    /// Swaps the automatic speed-ups for `found`, leaving any speed set by hand alone.
    public mutating func applyAutoSpeeds(_ found: [SpeedRange]) {
        let old = self
        speeds.removeAll(where: \.isAuto)
        let manual = speeds
        for range in found {
            var pieces = [(range.start, range.end)]
            for m in manual where m.clipID == range.clipID {
                pieces = pieces.flatMap { a, b -> [(Double, Double)] in
                    guard m.end > a, m.start < b else { return [(a, b)] }
                    return [(a, m.start), (m.end, b)].filter { $0.1 - $0.0 >= Self.minSegment }
                }
            }
            for (a, b) in pieces { replaceSpeed(range.speed, clipID: range.clipID, from: a, to: b, isAuto: true) }
        }
        retime(from: old)
    }

    public mutating func clearAutoSpeeds() { applyAutoSpeeds([]) }

    mutating func replaceSpeed(_ speed: Double, clipID: UUID, from a: Double, to b: Double, isAuto: Bool) {
        var kept: [SpeedRange] = []
        for r in speeds {
            guard r.clipID == clipID, r.end > a, r.start < b else {
                kept.append(r)
                continue
            }
            if r.start < a { kept.append(SpeedRange(clipID: clipID, start: r.start, end: a, speed: r.speed, isAuto: r.isAuto)) }
            if r.end > b { kept.append(SpeedRange(clipID: clipID, start: b, end: r.end, speed: r.speed, isAuto: r.isAuto)) }
        }
        if abs(speed - 1) > 1e-6, b - a >= Self.minSegment {
            kept.append(SpeedRange(clipID: clipID, start: a, end: b, speed: speed, isAuto: isAuto))
        }
        kept.sort { ($0.clipID.uuidString, $0.start) < ($1.clipID.uuidString, $1.start) }
        var merged: [SpeedRange] = []
        for r in kept {
            if var last = merged.last, last.clipID == r.clipID, abs(last.end - r.start) < 1e-6, last.speed == r.speed,
               last.isAuto == r.isAuto {
                last.end = r.end
                merged[merged.count - 1] = last
            } else {
                merged.append(r)
            }
        }
        speeds = merged
    }

    /// Moves everything placed in edit time (zooms, camera layouts, blurs) so each stays on the moment it covered in `old`.
    mutating func retime(from old: Project) {
        func map(_ t: Double) -> Double {
            guard let (ci, local) = old.sourceTime(edited: t), clips.indices.contains(ci) else { return t }
            return editedPosition(clipIndex: ci, local: local)
        }
        func span(_ a: Double, _ b: Double) -> (Double, Double)? {
            let (na, nb) = (map(a), map(b))
            return nb - na > 1e-3 ? (na, nb) : nil
        }
        cameraBlocks = cameraBlocks.compactMap { b in span(b.start, b.end).map { var b = b; (b.start, b.end) = $0; return b } }
        zoomBlocks = zoomBlocks.compactMap { b in span(b.start, b.end).map { var b = b; (b.start, b.end) = $0; return b } }
        redactions = redactions.compactMap { b in span(b.start, b.end).map { var b = b; (b.start, b.end) = $0; return b } }
        spotlights = spotlights.compactMap { b in span(b.start, b.end).map { var b = b; (b.start, b.end) = $0; return b } }
    }
}
