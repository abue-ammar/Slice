//
//  EditorModel+Transitions.swift
//  Slice
//
//  Created by rit3zh CX on 10/6/26.
//

import SliceCore
import SwiftUI

extension EditorModel {
    var selectedTransition: PlacedTransition? {
        guard case let .transition(id) = selection else { return nil }
        return project.placedTransitions.first { $0.transition.id == id }
    }

    func setTransition(into seg: Segment, kind: ClipTransition.Kind) {
        let id = project.setTransition(into: seg, kind: kind)
        selection = .transition(id)
        showTransition(id)
    }

    func setTransitionKind(_ id: UUID, _ kind: ClipTransition.Kind) {
        guard let placed = project.placedTransitions.first(where: { $0.transition.id == id }),
              placed.transition.kind != kind else { return }
        setTransition(into: placed.window.next, kind: kind)
    }

    func updateTransition(_ id: UUID, _ change: (inout ClipTransition) -> Void) {
        guard let i = project.transitions.firstIndex(where: { $0.id == id }) else { return }
        change(&project.transitions[i])
        project.transitions[i].duration = min(max(project.transitions[i].duration, ClipTransition.durationRange.lowerBound),
                                              ClipTransition.durationRange.upperBound)
    }

    func removeTransition(_ id: UUID) {
        project.transitions.removeAll { $0.id == id }
        if selection == .transition(id) { selection = nil }
    }

    private func showTransition(_ id: UUID) {
        guard !isPlaying, let placed = project.placedTransitions.first(where: { $0.transition.id == id }),
              !(placed.start ..< placed.end).contains(time) else { return }
        seek(to: placed.window.time)
    }
}

extension ClipTransition.Kind {
    var symbol: String {
        switch self {
        case .zoomBlur: "scope"
        case .pageCurl: "book.pages"
        case .revolve: "arrow.counterclockwise"
        case .burn: "flame"
        case .waveScramble: "water.waves"
        case .snap: "sparkles"
        }
    }
}
