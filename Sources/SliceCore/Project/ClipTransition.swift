//
//  ClipTransition.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/9/26.
//

import Foundation

public struct ClipTransition: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case zoomBlur, pageCurl, revolve, burn, waveScramble, snap

        public var name: String {
            switch self {
            case .zoomBlur: "Zoom Blur"
            case .pageCurl: "Page Curl"
            case .revolve: "Revolve"
            case .burn: "Burn"
            case .waveScramble: "Wave Scramble"
            case .snap: "Thanos Snap"
            }
        }

        public var defaultDuration: Double {
            switch self {
            case .zoomBlur: 0.8
            case .pageCurl, .waveScramble: 1
            case .revolve, .burn: 1.2
            case .snap: 1.6
            }
        }
    }

    public var id: UUID
    public var clipID: UUID
    public var time: Double
    public var kind: Kind
    public var duration: Double

    public static let durationRange = 0.2 ... 2.0

    public init(id: UUID = UUID(), clipID: UUID, time: Double, kind: Kind, duration: Double? = nil) {
        self.id = id
        self.clipID = clipID
        self.time = time
        self.kind = kind
        self.duration = duration ?? kind.defaultDuration
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        clipID = try c.decode(UUID.self, forKey: .clipID)
        time = try c.decode(Double.self, forKey: .time)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .zoomBlur
        let d = try c.decodeIfPresent(Double.self, forKey: .duration) ?? kind.defaultDuration
        duration = min(max(d, Self.durationRange.lowerBound), Self.durationRange.upperBound)
    }
}

public struct TransitionWindow: Equatable {
    public var time: Double
    public var room: Double
    public var previous: Segment
    public var next: Segment

    public var start: Double { time - room }
    public var end: Double { time + room }

    static let maxRoom = ClipTransition.durationRange.upperBound / 2
}

public struct PlacedTransition: Equatable {
    public var transition: ClipTransition
    public var window: TransitionWindow

    public var duration: Double { 2 * min(transition.duration / 2, window.room) }
    public var start: Double { window.time - duration / 2 }
    public var end: Double { window.time + duration / 2 }

    public func progress(at t: Double) -> Double? {
        guard duration > 0, t >= start, t < end else { return nil }
        return (t - start) / duration
    }
}

extension Project {
    public var transitionWindows: [TransitionWindow] { placedTransitions.map(\.window) }

    public var placedTransitions: [PlacedTransition] {
        guard !transitions.isEmpty else { return [] }
        let segs = segments
        var out: [PlacedTransition] = []
        for i in segs.indices.dropFirst() {
            let prev = segs[i - 1], next = segs[i]
            let id = clips[next.clipIndex].id
            guard let tr = transitions.last(where: { $0.clipID == id && abs($0.time - next.sourceStart) < 1e-3 }) else { continue }
            let room = min(TransitionWindow.maxRoom, prev.duration / 2, next.duration / 2)
            guard room > 0.01 else { continue }
            out.append(PlacedTransition(transition: tr, window: TransitionWindow(time: next.editedStart, room: room,
                                                                                 previous: prev, next: next)))
        }
        return out
    }

    public func transition(into seg: Segment) -> ClipTransition? {
        let id = clips[seg.clipIndex].id
        return transitions.last { $0.clipID == id && abs($0.time - seg.sourceStart) < 1e-3 }
    }

    @discardableResult
    public mutating func setTransition(into seg: Segment, kind: ClipTransition.Kind) -> UUID {
        let id = clips[seg.clipIndex].id
        let existing = transition(into: seg)
        transitions.removeAll { $0.clipID == id && abs($0.time - seg.sourceStart) < 1e-3 }
        var tr = ClipTransition(id: existing?.id ?? UUID(), clipID: id, time: seg.sourceStart, kind: kind)
        if let existing, abs(existing.duration - existing.kind.defaultDuration) > 1e-6 { tr.duration = existing.duration }
        transitions.append(tr)
        return tr.id
    }
}

extension Array where Element == PlacedTransition {
    public func active(at t: Double) -> (PlacedTransition, Double)? {
        for p in self { if let f = p.progress(at: t) { return (p, f) } }
        return nil
    }
}

extension Array where Element == TransitionWindow {
    public func window(at t: Double) -> TransitionWindow? {
        first { t >= $0.start && t < $0.end }
    }
}
