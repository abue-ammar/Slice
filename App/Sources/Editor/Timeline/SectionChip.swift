//
//  SectionChip.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import SliceCore
import SwiftUI

struct SectionChip: View {
    let label: String
    let segment: Segment
    let pps: CGFloat
    let height: CGFloat
    let selected: Bool
    let dimmed: Bool
    let tick: Double
    let clipDuration: Double
    let audio: ClipAudio
    @Binding var drag: TrimDrag?
    let snapTime: () -> Double
    let select: () -> Void
    let preview: (Double) -> Void
    let trim: (_ newStart: Double?, _ newEnd: Double?) -> Void

    @State private var hovering = false
    @State private var snapTarget: Double?
    @State private var snapped = false

    private var trimming: Bool { drag?.segment == segment }

    var body: some View {
        let delta = trimming ? drag?.delta ?? 0 : 0
        let leading = drag?.leading ?? false
        let start = segment.editedStart + (leading ? delta : 0)
        let length = segment.duration + (leading ? -delta : delta)
        let width = max(length * pps - 2, 4)
        let lit = hovering || selected || trimming
        let strength = dimmed && !trimming ? 0.42 : lit ? 1 : 0.9
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Theme.clip.opacity(strength), Theme.clip.opacity(strength * 0.8)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay { ticks(start: start, length: length).clipShape(shape) }
            .overlay {
                if !segment.isRetimed {
                    ClipWaveformView(audio: audio, sourceStart: segment.sourceStart + (leading ? delta : 0), pps: pps,
                                     strength: dimmed && !trimming ? 0.5 : 1)
                        .clipShape(shape)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if segment.isRetimed && width > 40 {
                    HStack(spacing: 3) {
                        Image(systemName: segment.isSlowed ? "tortoise.fill" : "hare.fill")
                        if width <= 70 { Text(SpeedRange.label(segment.speed)) }
                    }
                    .font(.rounded(9, .semibold))
                    .foregroundStyle(.white.opacity(dimmed && !trimming ? 0.3 : 0.6))
                    .padding(.leading, 10)
                    .padding(.bottom, 5)
                    .allowsHitTesting(false)
                } else if audio.isEmpty && width > 40 {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white.opacity(dimmed && !trimming ? 0.2 : 0.4))
                        .padding(.leading, 10)
                        .padding(.bottom, 5)
                        .allowsHitTesting(false)
                }
            }
            .overlay(shape.strokeBorder(Color.white.opacity(selected || trimming ? 0.9 : hovering ? 0.3 : 0.12),
                                        lineWidth: selected || trimming ? 2 : 1))
            .overlay {
                if width > 70 {
                    VStack(spacing: 0) {
                        Text(label).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                        Text((segment.isRetimed ? SpeedRange.label(segment.speed) + " · " : "") + CutPin.label(length, precise: trimming))
                            .font(.rounded(12).monospacedDigit())
                            .foregroundStyle(.white)
                            .contentTransition(.numericText(value: length))
                    }
                    .lineLimit(1)
                    .opacity(dimmed && !trimming ? 0.55 : 1)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .leading) { handle(leading: true) }
            .overlay(alignment: .trailing) { handle(leading: false) }
            .frame(width: width, height: height)
            .shadow(color: Theme.clip.opacity(lit && !dimmed ? 0.4 : 0), radius: 8, y: 2)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.hover, value: selected)
            .animation(Theme.hover, value: dimmed)
            .offset(x: start * pps + 1)
            .onTapGesture(perform: select)
    }

    private func ticks(start: Double, length: Double) -> some View {
        Canvas { ctx, size in
            var t = ((start + 0.001) / tick).rounded(.up) * tick
            while t < start + length - 0.001 {
                let x = (t - start) * pps - 1
                ctx.fill(Path(CGRect(x: x - 0.5, y: 0, width: 1, height: size.height)), with: .color(.white.opacity(0.1)))
                t += tick
            }
        }
        .allowsHitTesting(false)
    }

    private func handle(leading: Bool) -> some View {
        EdgeHandle(visible: hovering || selected || trimming) { dx in
            if !trimming {
                snapTarget = snapTime()
                select()
            }
            let edge = leading ? segment.editedStart : segment.editedEnd
            var dt = dx / pps
            let snap = snapTarget.map { abs(edge + dt - $0) * pps < 6 } ?? false
            if snap, let target = snapTarget { dt = target - edge }
            if snap, !snapped { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            snapped = snap
            let speed = segment.speed
            if leading {
                dt = min(max(dt, -segment.sourceStart / speed), segment.duration - 0.1 / speed)
            } else {
                dt = max(min(dt, (clipDuration - segment.sourceEnd) / speed), -(segment.duration - 0.1 / speed))
            }
            drag = TrimDrag(segment: segment, leading: leading, delta: dt)
            if leading, dt > 0 { preview(edge + dt) }
            if !leading, dt < 0 { preview(edge + dt - 1.0 / 60) }
        } onEnded: {
            guard let d = drag, d.segment == segment else { return }
            drag = nil
            snapped = false
            snapTarget = nil
            guard abs(d.delta) > 0.01 else { return }
            let source = d.delta * segment.speed
            if leading { trim(segment.sourceStart + source, nil) } else { trim(nil, segment.sourceEnd + source) }
            preview(leading ? segment.editedStart : segment.editedEnd + d.delta)
        }
        .help(leading ? "Drag to trim the start" : "Drag to trim the end")
    }
}
