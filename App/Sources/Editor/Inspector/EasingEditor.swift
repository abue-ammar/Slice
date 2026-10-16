//
//  EasingEditor.swift
//  Slice
//
//  Created by rit3zh CX on 10/6/26.
//

import AppKit
import SliceCore
import SwiftUI

struct EasingEditor: View {
    @Binding var curve: CubicBezier
    let zoomDuration: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pausedOverride: Bool?
    @State private var loopStart = Date()

    private var paused: Bool { pausedOverride ?? reduceMotion }
    private var duration: Double { max(zoomDuration, 0.1) }
    private var active: CurvePreset? { CurvePreset.all.first { $0.curve == curve } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SwiftUI.TimelineView(.animation(minimumInterval: nil, paused: paused)) { context in
                let phase = LoopPhase(elapsed: context.date.timeIntervalSince(loopStart), duration: duration)
                VStack(alignment: .leading, spacing: 10) {
                    CurveGraph(curve: $curve, tracer: phase.tracer.map { ($0.time, curve($0.time), $0.opacity) })
                    preview(progress: phase.progress(curve))
                }
            }
            presets
            MoreOptions("Copy or paste as CSS", id: "easingCSS") { CurveCodeField(curve: $curve) }
        }
        .animation(.snappy(duration: 0.2), value: active?.name)
    }

    // MARK: - Preview

    private func preview(progress: Double) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                let travel = geo.size.width - 16
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.control)
                    Circle().fill(.white).frame(width: 16, height: 16)
                        .offset(x: travel * progress)
                }
            }
            .frame(height: 16)
            .padding(4)
            .background(Capsule().fill(Theme.control))
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white)
                    .scaleEffect(0.5 + 0.5 * progress)
            }
            .frame(width: 22, height: 22)
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control))
            Button {
                pausedOverride = !paused
            } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(IconButtonStyle(size: 28, iconSize: 11))
            .help(paused ? "Play preview" : "Pause preview")
        }
    }

    // MARK: - Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Drag the two dots to shape the motion, or start from one of these.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(CurvePreset.all, id: \.name) { preset in
                    let on = preset.curve == curve
                    Button { curve = preset.curve } label: {
                        Text(preset.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(on ? Theme.accent : .secondary)
                            .frame(maxWidth: .infinity, minHeight: 26)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(on ? Theme.accent.opacity(0.15) : Theme.control))
                            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(active?.use ?? "Your own curve.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 32, alignment: .topLeading)
                .id(active?.name ?? "custom")
                .transition(.opacity)
        }
    }
}

private struct CurvePreset {
    let name: String
    let curve: CubicBezier
    let use: String

    static let all: [CurvePreset] = CubicBezier.presets.map { p in
        switch p.name {
        case "ease-out": CurvePreset(name: "Quick", curve: p.curve, use: "Arrives fast and lands softly. Feels instant.")
        case "ease-in-out": CurvePreset(name: "Smooth", curve: p.curve, use: "Speeds up, then settles, like a deliberate camera move.")
        case "iOS drawer": CurvePreset(name: "Soft landing", curve: p.curve, use: "Quick off the mark, with a long gentle landing.")
        case "ease": CurvePreset(name: "Relaxed", curve: p.curve, use: "Soft and unhurried.")
        case "linear": CurvePreset(name: "Steady", curve: p.curve, use: "The same speed all the way. Good for slow drifts.")
        case "overshoot": CurvePreset(name: "Playful", curve: p.curve, use: "Goes a touch too far, then eases back. Use sparingly.")
        default: CurvePreset(name: p.name, curve: p.curve, use: p.use)
        }
    }
}

struct LoopPhase {
    static let hold = 0.7
    let elapsed: Double
    let duration: Double

    private var total: Double { 2 * duration + 2 * Self.hold }
    private var t: Double { elapsed.truncatingRemainder(dividingBy: total) }

    func progress(_ curve: CubicBezier) -> Double {
        let t = t
        if t < duration { return curve(t / duration) }
        if t < duration + Self.hold { return 1 }
        if t < 2 * duration + Self.hold { return 1 - curve((t - duration - Self.hold) / duration) }
        return 0
    }

    var tracer: (time: Double, opacity: Double)? {
        let t = t
        if t < duration { return (t / duration, 1) }
        let since = t - duration - Self.hold
        guard since < 0.15 else { return nil }
        return (1, since < 0 ? 1 : 1 - since / 0.15)
    }
}

// MARK: - Code field

private struct CurveCodeField: View {
    @Binding var curve: CubicBezier
    @State private var text = ""
    @State private var invalid = false
    @State private var copied = false
    @State private var copyReset: Task<Void, Never>?
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField("cubic-bezier(…)", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .focused($editing)
                .onSubmit(commit)
                .onChange(of: editing) { _, now in if !now { commit() } }
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(IconButtonStyle(size: 26, iconSize: 11))
            .help("Copy as CSS")
            Button(action: paste) {
                Image(systemName: "doc.on.clipboard")
            }
            .buttonStyle(IconButtonStyle(size: 26, iconSize: 11))
            .help("Paste a cubic-bezier() curve")
        }
        .padding(.leading, 10)
        .padding(.trailing, 3)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Theme.control))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(invalid ? Color.red.opacity(0.7) : Theme.stroke))
        .onAppear { text = curve.css }
        .onChange(of: curve) { _, new in if !editing { text = new.css } }
        .onDisappear { copyReset?.cancel() }
        .animation(Theme.hover, value: invalid)
    }

    private func commit() {
        if let parsed = CubicBezier(css: text) {
            curve = parsed
            text = parsed.css
            invalid = false
        } else {
            invalid = true
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.9))
                invalid = false
                if !editing { text = curve.css }
            }
        }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curve.css, forType: .string)
        copied = true
        copyReset?.cancel()
        copyReset = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if !Task.isCancelled { copied = false }
        }
    }

    private func paste() {
        guard let string = NSPasteboard.general.string(forType: .string) else { return }
        text = string
        commit()
    }
}

struct EasingThumbnail: View {
    let ease: (Double) -> Double

    var body: some View {
        Canvas { ctx, size in
            let pr = CurveGraph.progress
            func y(_ p: Double) -> CGFloat { (pr.upperBound - p) / (pr.upperBound - pr.lowerBound) * size.height }
            var frame = Path()
            frame.move(to: CGPoint(x: 0, y: y(0))); frame.addLine(to: CGPoint(x: size.width, y: y(0)))
            frame.move(to: CGPoint(x: 0, y: y(1))); frame.addLine(to: CGPoint(x: size.width, y: y(1)))
            ctx.stroke(frame, with: .color(.white.opacity(0.1)), lineWidth: 1)
            var path = Path()
            for i in 0 ... 40 {
                let x = Double(i) / 40
                let point = CGPoint(x: x * size.width, y: y(ease(x)))
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            ctx.stroke(path, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(width: 34, height: 26)
        .accessibilityHidden(true)
    }
}
