//
//  EditorModel+Spotlight.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import Foundation
import SliceCore

extension EditorModel {
    var spotlightRanges: [(id: UUID, start: Double, end: Double)] { project.spotlights.map { ($0.id, $0.start, $0.end) } }

    var selectedSpotlight: SpotlightBlock? {
        guard case let .spotlight(id) = selection else { return nil }
        return project.spotlights.first { $0.id == id }
    }

    /// While a spotlight is selected the preview shows the whole screen, so its circle can be placed on what it lights.
    var isEditingSpotlight: Bool {
        guard let b = selectedSpotlight, !b.followsPointer, !isPlaying else { return false }
        return true
    }

    /// Starts on the first click in its span when there is one, else where the pointer is, with the look the click
    /// spotlights use.
    func addSpotlight(at t: Double) {
        guard let range = proposedRange(.spotlight, at: t) else { return }
        let look = project.cursor.spotlight
        let click = cursorTrack.clicks.first { range.contains($0.t) }
        let center = click?.point ?? cursorTrack.position(at: range.lowerBound) ?? CGPoint(x: 0.5, y: 0.5)
        let block = SpotlightBlock(start: range.lowerBound, end: range.upperBound, center: SpotlightBlock.clamped(center),
                                   mode: look.mode, size: look.size, strength: look.strength)
        project.spotlights.append(block)
        selection = .spotlight(block.id)
        seek(to: range.lowerBound + min(0.5, (range.upperBound - range.lowerBound) / 2))
    }

    func setSpotlightRange(_ id: UUID, start: Double, end: Double) {
        guard let i = project.spotlights.firstIndex(where: { $0.id == id }) else { return }
        let r = clamp(start: start, end: end, current: project.spotlights[i].start ..< project.spotlights[i].end,
                      ranges: spotlightRanges, id: id)
        project.spotlights[i].start = r.lowerBound
        project.spotlights[i].end = r.upperBound
    }

    func updateSpotlight(_ id: UUID, _ change: (inout SpotlightBlock) -> Void) {
        guard let i = project.spotlights.firstIndex(where: { $0.id == id }) else { return }
        var b = project.spotlights[i]
        change(&b)
        b.center = SpotlightBlock.clamped(b.center)
        project.spotlights[i] = b
    }

    /// Past the fade-in, so the circle shows fully while it's placed.
    func revealSelectedSpotlight() {
        guard let b = selectedSpotlight, !b.isActive(at: time) else { return }
        seek(to: b.start + min(0.5, (b.end - b.start) / 2))
    }
}
