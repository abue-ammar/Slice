//
//  LiveBarControls.swift
//  Slice
//
//  Created by rit3zh CX on 10/21/26.
//

import SwiftUI

/// Stop, with the time recorded so far beside it; the time breathes while paused.
struct FinishButton: View {
    let elapsed: Double
    let paused: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    Circle().fill(Color(red: 0.98, green: 0.36, blue: 0.34).opacity(hovering ? 1 : 0.92))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white)
                        .frame(width: 7.5, height: 7.5)
                }
                .frame(width: 22, height: 22)
                Text(Self.format(elapsed))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.92))
                    .contentTransition(.numericText(value: elapsed.rounded(.down)))
                    .animation(.smooth(duration: 0.3), value: Int(elapsed))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(Breathing(on: paused))
            }
            .padding(.horizontal, 12)
            .frame(width: LiveBar.finish, height: 44)
            .background(shape.fill(Color.white.opacity(hovering ? 0.1 : 0)))
            .contentShape(shape)
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .help("Finish recording")
        .onHover { hovering = $0 }
        .animation(Bar.hover, value: hovering)
    }

    static func format(_ seconds: Double) -> String {
        let t = Int(seconds), h = t / 3600, m = t / 60 % 60, s = t % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

/// A ring with pause's two bars, which fold into the play triangle as the ring fills with the accent and breathes.
struct PauseButton: View {
    let paused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            let glyph = PlayPauseShape(play: paused ? 1 : 0)
            ZStack {
                if paused { PausedHalo().transition(.opacity) }
                Circle().fill(Theme.accent).opacity(paused ? 1 : 0)
                Circle().strokeBorder(.white, lineWidth: 1.8).opacity(paused ? 0 : 1)
                glyph
                    .fill(.white)
                    .overlay(glyph.stroke(.white, style: StrokeStyle(lineWidth: 1.6, lineJoin: .round)))
                    .frame(width: 7.5, height: 8.5)
            }
            .frame(width: 22, height: 22)
        }
        .buttonStyle(LiveIconStyle())
        .help(paused ? "Resume recording" : "Pause recording")
        .accessibilityLabel(paused ? "Resume" : "Pause")
        .animation(.smooth(duration: 0.38), value: paused)
    }
}

struct LiveIcon: View {
    let symbol: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(LiveIconStyle())
        .help(help)
    }
}

struct LiveDrawButton: View {
    @ObservedObject var session: AnnotationSession

    var body: some View {
        Button { AnnotationController.shared.toggleDrawing() } label: {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 16, weight: .medium))
        }
        .buttonStyle(LiveIconStyle(tint: session.isActive ? Theme.accent : nil))
        .help(session.isActive ? "Stop drawing (esc)" : "Draw on screen (\(AnnotationController.toggleLabel))")
    }
}

/// The live bar's plain icons: no chrome until hovered, filled with `tint` while on.
struct LiveIconStyle: ButtonStyle {
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View { LiveIconBody(configuration: configuration, tint: tint) }
}

private struct LiveIconBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color?
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        configuration.label
            .foregroundStyle(.white.opacity(hovering || tint != nil ? 1 : 0.85))
            .frame(width: LiveBar.icon, height: 44)
            .background(shape.fill(tint?.opacity(hovering ? 0.95 : 0.85) ?? Color.white.opacity(hovering ? 0.1 : 0)))
            .contentShape(shape)
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .onHover { hovering = $0 }
            .animation(Bar.hover, value: hovering)
            .animation(Bar.press, value: configuration.isPressed)
            .animation(.smooth(duration: 0.3), value: tint == nil)
    }
}

/// Pause's two bars at 0, the play triangle at 1: the left bar becomes the triangle's back half, the right its point.
private struct PlayPauseShape: Shape {
    var play: Double

    var animatableData: Double {
        get { play }
        set { play = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let pause: [[CGPoint]] = [
            [CGPoint(x: 0.04, y: 0.04), CGPoint(x: 0.34, y: 0.04), CGPoint(x: 0.34, y: 0.96), CGPoint(x: 0.04, y: 0.96)],
            [CGPoint(x: 0.66, y: 0.04), CGPoint(x: 0.96, y: 0.04), CGPoint(x: 0.96, y: 0.96), CGPoint(x: 0.66, y: 0.96)],
        ]
        // Nudged right of centre, where a triangle looks centred.
        let a = CGPoint(x: 0.14, y: 0), b = CGPoint(x: 1.1, y: 0.5), c = CGPoint(x: 0.14, y: 1)
        let top = CGPoint(x: 0.62, y: 0.25), bottom = CGPoint(x: 0.62, y: 0.75)
        let triangle: [[CGPoint]] = [[a, top, bottom, c], [top, b, b, bottom]]
        var path = Path()
        for (from, to) in zip(pause, triangle) {
            let points = zip(from, to).map { p, q in
                CGPoint(x: rect.minX + (p.x + (q.x - p.x) * play) * rect.width,
                        y: rect.minY + (p.y + (q.y - p.y) * play) * rect.height)
            }
            path.addLines(points)
            path.closeSubpath()
        }
        return path
    }
}

/// A slow, soft swell of the accent around the ring while the recording waits.
private struct PausedHalo: View {
    @State private var start = Date()

    var body: some View {
        SwiftUI.TimelineView(.animation) { context in
            let swell = Breathing.swell(context.date.timeIntervalSince(start))
            Circle()
                .fill(Theme.accent)
                .scaleEffect(1 + 0.45 * swell)
                .opacity(0.12 + 0.3 * swell)
                .blur(radius: 3)
        }
        .allowsHitTesting(false)
    }
}

/// Fades gently in and out while `on`, starting from full each time it comes on and settling back when it goes off.
private struct Breathing: ViewModifier {
    let on: Bool
    @State private var start = Date()

    static func swell(_ t: Double) -> Double {
        (1 - cos(t.truncatingRemainder(dividingBy: 2.2) / 2.2 * 2 * .pi)) / 2
    }

    func body(content: Content) -> some View {
        SwiftUI.TimelineView(.animation(paused: !on)) { context in
            content.opacity(on ? 1 - 0.6 * Self.swell(context.date.timeIntervalSince(start)) : 1)
        }
        .animation(.smooth(duration: 0.3), value: on)
        .onChange(of: on) { if on { start = Date() } }
    }
}
