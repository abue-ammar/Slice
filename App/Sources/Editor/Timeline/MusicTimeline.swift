//
//  MusicTimeline.swift
//  Slice
//
//  Created by rit3zh CX on 10/13/26.
//

import SliceCore
import SwiftUI

struct MusicLaneContent: View {
    @ObservedObject var editor: EditorModel
    let pps: CGFloat
    let height: CGFloat

    var body: some View {
        let project = editor.project
        let duck = project.duckingEnvelope
        ForEach(project.music) { clip in
            MusicBlock(clip: clip, duration: project.duration, shape: project.musicShape(for: clip, ducking: duck),
                       url: editor.musicURL(clip.source), muted: project.audio.musicMuted || clip.volume <= 0,
                       pps: pps, height: height, selected: editor.selection == .music(clip.id),
                       select: { editor.selection = .music(clip.id) },
                       move: { editor.moveMusic(clip.id, to: $0) },
                       trim: { editor.trimMusic(clip.id, start: $0, end: $1) })
        }
    }
}

struct MusicBlock: View {
    let clip: MusicClip
    let duration: Double
    let shape: GainEnvelope
    let url: URL?
    let muted: Bool
    let pps: CGFloat
    let height: CGFloat
    let selected: Bool
    let select: () -> Void
    let move: (Double) -> Void
    let trim: (Double?, Double?) -> Void

    @ObservedObject private var summaries = AudioSummaries.shared
    @State private var origin: (start: Double, end: Double)?
    @State private var hovering = false

    var body: some View {
        let end = min(clip.nominalEnd(duration: duration), max(duration, clip.start))
        let width = max((end - clip.start) * pps, 6)
        let lit = hovering || selected
        let missing = url == nil
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let tint = missing ? Color.orange : Theme.music
        shape
            .fill(LinearGradient(colors: [tint.opacity(lit ? 0.75 : 0.6), tint.opacity(lit ? 0.6 : 0.45)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { waveform(end: end).clipShape(shape).opacity(muted ? 0.35 : 1) }
            .overlay(shape.strokeBorder(Color.white.opacity(selected ? 0.9 : hovering ? 0.3 : 0.12), lineWidth: selected ? 2 : 1))
            .overlay(alignment: .topLeading) {
                if width > 60 { label(missing: missing).padding(.leading, 10).padding(.top, 5).allowsHitTesting(false) }
            }
            .overlay(alignment: .leading) { handle(leading: true) }
            .overlay(alignment: .trailing) { handle(leading: false) }
            .frame(width: width, height: height)
            .shadow(color: tint.opacity(lit ? 0.4 : 0), radius: 8, y: 2)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.hover, value: selected)
            .offset(x: clip.start * pps)
            .onTapGesture { select() }
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { v in
                    if origin == nil {
                        origin = (clip.start, end)
                        select()
                    }
                    move(origin!.start + v.translation.width / pps)
                }
                .onEnded { _ in origin = nil })
            .task(id: url) { if let url { _ = await summaries.load(url) } }
            .help(missing ? "\(clip.name) is missing. Select it to locate the file or pick another track." : clip.name)
    }

    private func label(missing: Bool) -> some View {
        HStack(spacing: 4) {
            if missing || muted {
                Image(systemName: missing ? "exclamationmark.triangle.fill" : "speaker.slash.fill")
            } else {
                MusicOrb(source: clip.source).frame(width: 11, height: 11)
            }
            Text(missing ? "\(clip.name) · missing" : clip.name)
            if clip.loops && !missing { Image(systemName: "repeat").foregroundStyle(.white.opacity(0.6)) }
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .lineLimit(1)
        .shadow(color: .black.opacity(0.3), radius: 2)
    }

    private func waveform(end: Double) -> some View {
        let summary = url.flatMap { summaries.summaries[$0] }
        let pieces = clip.pieces(duration: duration)
        let start = clip.start
        return Canvas { ctx, size in
            let mid = size.height / 2
            for p in pieces.dropFirst() {
                let x = (p.at - start) * pps
                ctx.fill(Path(CGRect(x: x, y: 4, width: 1, height: size.height - 8)), with: .color(.white.opacity(0.22)))
            }
            guard let summary else { return }
            let step: CGFloat = 3
            var x: CGFloat = 1.5
            var bars = Path()
            while x < size.width - 1 {
                let t = start + Double(x) / Double(pps)
                if let piece = pieces.last(where: { $0.at <= t && t <= $0.end }) {
                    let level = pow(Double(summary.level(at: piece.from + (t - piece.at))), 0.6) * shape.value(at: t)
                    let h = max(CGFloat(level) * (size.height - 14), 1)
                    bars.addRoundedRect(in: CGRect(x: x - 0.75, y: mid - h / 2, width: 1.5, height: h),
                                        cornerSize: CGSize(width: 0.75, height: 0.75))
                }
                x += step
            }
            ctx.fill(bars, with: .color(.white.opacity(0.55)))
        }
        .allowsHitTesting(false)
    }

    private func handle(leading: Bool) -> some View {
        EdgeHandle(visible: hovering || selected) { dx in
            if origin == nil {
                origin = (clip.start, clip.nominalEnd(duration: duration))
                select()
            }
            let dt = dx / pps
            if leading { trim(origin!.start + dt, nil) } else { trim(nil, origin!.end + dt) }
        } onEnded: { origin = nil }
        .help(leading ? "Drag to trim the start" : "Drag to trim the end")
    }
}
