//
//  SpotlightModel.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import CoreGraphics
import Foundation

/// A spotlight placed by hand on the timeline: a spot on the screen, or the pointer, kept in focus for a while.
public struct SpotlightBlock: Codable, Equatable, Identifiable {
    public var id: UUID
    public var start: Double
    public var end: Double
    /// A fraction of the screen, with a top-left origin.
    public var center: CGPoint
    public var followsPointer: Bool
    public var mode: SpotlightMode
    public var size: Double
    public var strength: Double

    public init(id: UUID = UUID(), start: Double, end: Double, center: CGPoint = CGPoint(x: 0.5, y: 0.5),
                followsPointer: Bool = false, mode: SpotlightMode = .dim, size: Double = 1, strength: Double = 0.55) {
        self.id = id
        self.start = start
        self.end = end
        self.center = center
        self.followsPointer = followsPointer
        self.mode = mode
        self.size = size
        self.strength = strength
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SpotlightBlock(start: 0, end: 0)
        id = try c.decode(UUID.self, forKey: .id)
        start = try c.decode(Double.self, forKey: .start)
        end = try c.decode(Double.self, forKey: .end)
        center = try c.decodeIfPresent(CGPoint.self, forKey: .center) ?? d.center
        followsPointer = try c.decodeIfPresent(Bool.self, forKey: .followsPointer) ?? d.followsPointer
        mode = (try? c.decodeIfPresent(SpotlightMode.self, forKey: .mode)) ?? d.mode
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        strength = try c.decodeIfPresent(Double.self, forKey: .strength) ?? d.strength
    }

    public func isActive(at t: Double) -> Bool { t >= start && t < end }

    public static func clamped(_ p: CGPoint) -> CGPoint { CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1)) }
}

extension RenderScene {
    /// The spotlight at `t`: a block placed by hand, the clicks', or both. A block owns the circle while it shows. It
    /// takes it over from a click's across its fade-in, and gives it back across its fade-out, or, when a click lands
    /// as it fades, glides over to that click.
    public func spotlight(at t: Double) -> SpotlightState? {
        let clicks = clickSpotlight(at: t)
        let blocks = project.spotlights.sorted { $0.start < $1.start }
        let placed = placedSpotlight(blocks, at: t)
        let i = blocks.lastIndex { $0.start <= t && t < $0.end } ?? blocks.lastIndex { $0.end <= t && t < $0.end + ClickSpotlight.glide }
        let landed = i.flatMap { clickLanding(blocks, index: $0) }
        if let clicks, let i, let landed, landed <= t {
            let from = entered(placedSpotlight(blocks, index: i, at: landed), at: landed)
            var s = SpotlightState.interpolate(from, clicks, smootherstep((t - landed) / ClickSpotlight.glide))
            s.amount = max(clicks.amount, placed?.state.amount ?? 0)
            return s
        }
        guard let placed else { return clicks }
        var s = entered(placed, at: t)
        if !placed.joinedAfter, landed == nil, let clicks, clickSpotlight(at: placed.block.end) != nil {
            s = .interpolate(clicks, s, placed.stay)
        }
        s.amount = max(clicks?.amount ?? 0, placed.state.amount)
        return s
    }

    /// The block's own state, taking over from the click spotlight that was showing as it began.
    private func entered(_ placed: PlacedSpotlight, at t: Double) -> SpotlightState {
        let b = placed.block
        guard !placed.joinedBefore, t - b.start < ClickSpotlight.glide, let from = clickSpotlight(at: b.start) else {
            return placed.state
        }
        var s = SpotlightState.interpolate(from, placed.state, smootherstep((t - b.start) / ClickSpotlight.glide))
        s.amount = placed.state.amount
        return s
    }

    /// When a click lands as the block fades out, the circle glides on to it, running past the block's end until
    /// it's there, rather than fading back to whatever was showing before.
    private func clickLanding(_ blocks: [SpotlightBlock], index i: Int) -> Double? {
        let b = blocks[i]
        let fadeOut = spotlightFadeOut(blocks, index: i)
        guard project.cursor.spotlight.enabled, fadeOut > 0 else { return nil }
        return cursor.clicks.lazy.map { $0.t - ClickSpotlight.lead }.first { $0 >= b.end - fadeOut && $0 < b.end }
    }

    static let spotlightJoinTolerance = 0.04

    private struct PlacedSpotlight {
        var state: SpotlightState
        var block: SpotlightBlock
        var joinedBefore: Bool
        var joinedAfter: Bool
        var stay: Double
    }

    private func placedSpotlight(_ blocks: [SpotlightBlock], at t: Double) -> PlacedSpotlight? {
        guard let i = blocks.lastIndex(where: { $0.isActive(at: t) }) else { return nil }
        let placed = placedSpotlight(blocks, index: i, at: t)
        return placed.state.amount > 0.001 ? placed : nil
    }

    /// Blocks that touch run on as one: no fade between them, and the circle glides from one's spot to the next.
    private func placedSpotlight(_ blocks: [SpotlightBlock], index i: Int, at t: Double) -> PlacedSpotlight {
        let b = blocks[i]
        let length = b.end - b.start
        let joinedBefore = i > 0 && b.start - blocks[i - 1].end < Self.spotlightJoinTolerance
        let joinedAfter = i + 1 < blocks.count && blocks[i + 1].start - b.end < Self.spotlightJoinTolerance
        let fadeOut = spotlightFadeOut(blocks, index: i)
        let rise = joinedBefore ? 1 : smootherstep((t - b.start) / min(ClickSpotlight.fadeIn, length / 2))
        let stay = joinedAfter ? 1 : smootherstep((b.end - t) / fadeOut)
        let look = b.mode.look(strength: b.strength)
        var state = SpotlightState(center: spotlightCenter(b, at: t), amount: rise * stay, size: b.size,
                                   darkness: look.darkness, blur: look.blur)
        let glide = min(ClickSpotlight.glide, length / 2)
        if joinedBefore, t - b.start < glide {
            let from = placedSpotlight(blocks, index: i - 1, at: max(blocks[i - 1].end - 1e-4, blocks[i - 1].start)).state
            let amount = state.amount
            state = .interpolate(from, state, smootherstep((t - b.start) / glide))
            state.amount = amount
        }
        return PlacedSpotlight(state: state, block: b, joinedBefore: joinedBefore, joinedAfter: joinedAfter, stay: stay)
    }

    private func spotlightFadeOut(_ blocks: [SpotlightBlock], index i: Int) -> Double {
        let b = blocks[i]
        let joinedAfter = i + 1 < blocks.count && blocks[i + 1].start - b.end < Self.spotlightJoinTolerance
        return joinedAfter ? 0 : min(ClickSpotlight.fadeOut, (b.end - b.start) / 2)
    }

    /// The pointer as it's drawn, so the circle sits on it exactly; the logged track when the pointer's hidden.
    func spotlightCenter(_ b: SpotlightBlock, at t: Double) -> CGPoint {
        guard b.followsPointer else { return SpotlightBlock.clamped(b.center) }
        return pointer(at: t)?.position ?? cursor.position(at: t) ?? SpotlightBlock.clamped(b.center)
    }
}
