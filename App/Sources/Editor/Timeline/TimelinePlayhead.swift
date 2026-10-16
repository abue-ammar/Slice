//
//  TimelinePlayhead.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import SliceCore
import SwiftUI

struct Playhead: View {
    static let width: CGFloat = 13
    var color: Color = .white
    var lineWidth: CGFloat = 2

    var body: some View {
        VStack(spacing: -1) {
            PinShape().fill(color).frame(width: Self.width, height: 16)
            Rectangle().fill(color).frame(width: lineWidth)
        }
        .frame(width: Self.width)
    }
}

struct PlayheadTrack: View {
    let editor: EditorModel
    @ObservedObject var clock: PlaybackClock
    let pps: CGFloat
    let height: CGFloat

    var body: some View {
        SwiftUI.TimelineView(.animation(paused: !clock.isPlaying)) { _ in
            Playhead()
                .shadow(color: .black.opacity(0.5), radius: 3)
                .frame(height: height)
                .offset(x: editor.liveTime * pps - Playhead.width / 2)
                .transaction { $0.animation = nil }
                .allowsHitTesting(false)
        }
    }
}

@Observable
final class Pointer {
    private(set) var x: CGFloat = 0
    private(set) var inside = false
    /// Hover regions on blocks briefly end the tracks' hover as the mouse crosses into them; ignore those blips.
    @ObservationIgnored private var leaving: DispatchWorkItem?

    func move(to x: CGFloat) {
        leaving?.cancel()
        leaving = nil
        self.x = x
        if !inside { inside = true }
    }

    func leave() {
        leaving?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.inside = false }
        leaving = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
}

struct GhostPlayhead: View {
    let pointer: Pointer
    @ObservedObject var clock: PlaybackClock
    let pps: CGFloat
    let height: CGFloat

    var body: some View {
        let x = pointer.x
        let shown = pointer.inside && abs(x - clock.time * pps) > 4
        Playhead(color: .white.opacity(0.28), lineWidth: 1)
            .frame(height: height)
            .offset(x: x - Playhead.width / 2)
            .transaction { $0.animation = nil }
            .animation(Theme.hover) { $0.opacity(shown ? 1 : 0) }
            .allowsHitTesting(false)
    }
}
