//
//  MotionPicker.swift
//  Slice
//
//  Created by rit3zh CX on 10/6/26.
//

import AppKit
import SliceCore
import SwiftUI

extension EasingCurve {
    var summary: String {
        switch self {
        case .smooth: "Starts softly and glides to a gentle stop, like a camera move. A good default."
        case .gentle: "Softer and calmer. Takes its time to get going."
        case .snappy: "Jumps in fast, then lands softly. Feels instant."
        case .spring: "Quick, with a soft settle at the end."
        case .easeIn: "Starts slow and speeds up as it arrives."
        case .easeOut: "Starts fast and slows down as it arrives."
        case .linear: "The same speed all the way. Good for slow drifts."
        case .custom: "Your own motion. Drag the dots below to shape it."
        }
    }
}

struct MotionPicker: View {
    @Binding var easing: EasingCurve
    @Binding var curve: CubicBezier
    let duration: Double
    /// Where "More styles" remembers being open.
    var id = "zoomMotion"

    private static let main: [EasingCurve] = [.smooth, .gentle, .snappy, .spring]
    private static let more: [EasingCurve] = [.easeIn, .easeOut, .linear, .custom]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            row(Self.main)
            Text(easing.summary)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .id(easing)
                .transition(.opacity)
            MoreOptions("More styles", id: id, pinned: Self.more.contains(easing)) {
                row(Self.more)
                if easing == .custom {
                    EasingEditor(curve: $curve, zoomDuration: duration)
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: easing)
    }

    private func row(_ options: [EasingCurve]) -> some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                MotionCard(label: option.label, ease: option == .custom ? { curve($0) } : { option($0) },
                           selected: option == easing) { easing = option }
            }
        }
    }
}

private struct MotionCard: View {
    let label: String
    let ease: (Double) -> Double
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false
    @State private var since = Date()

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            VStack(spacing: 5) {
                SwiftUI.TimelineView(.animation(paused: !hovering)) { context in
                    MotionSwatch(ease: ease, at: hovering ? LoopPhase(elapsed: context.date.timeIntervalSince(since), duration: 0.8).tracer : nil)
                }
                .frame(height: 30)
                Text(label)
                    .font(.system(size: 11, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(Theme.control, in: shape)
            .overlay(shape.strokeBorder(selected ? Theme.accent : Color.white.opacity(hovering ? 0.16 : 0.06),
                                        lineWidth: selected ? 2 : 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside && !hovering { since = Date() }
            hovering = inside
        }
        .animation(Theme.hover, value: hovering)
        .animation(Theme.hover, value: selected)
    }
}

private struct MotionSwatch: View {
    let ease: (Double) -> Double
    let at: (time: Double, opacity: Double)?

    var body: some View {
        Canvas { ctx, size in
            let inset: CGFloat = 4
            let w = size.width - inset * 2, h = size.height - inset * 2
            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: inset + x * w, y: inset + (1.1 - y) / 1.2 * h)
            }
            var path = Path()
            for i in 0 ... 32 {
                let x = Double(i) / 32
                if i == 0 { path.move(to: point(x, ease(x))) } else { path.addLine(to: point(x, ease(x))) }
            }
            ctx.stroke(path, with: .color(.white.opacity(at == nil ? 0.55 : 0.8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            if let at {
                let p = point(at.time, ease(at.time))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)),
                         with: .color(.white.opacity(at.opacity)))
            }
        }
        .accessibilityHidden(true)
    }
}
