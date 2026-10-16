//
//  CurveGraph.swift
//  Slice
//
//  Created by rit3zh CX on 10/6/26.
//

import AppKit
import SliceCore
import SwiftUI

struct CurveGraph: View {
    @Binding var curve: CubicBezier
    let tracer: (time: Double, progress: Double, opacity: Double)?

    static let time = 0.0 ... 1.0
    static let progress = -0.5 ... 1.5
    private static let step = 0.01
    private static let bigStep = 0.1

    @FocusState private var focused: Int?
    @State private var dragging: Int?

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let map = GraphMapping(size: size)
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(in: &ctx, map: map) }
                if let tracer {
                    Circle()
                        .fill(.white)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().strokeBorder(Theme.panel, lineWidth: 2))
                        .position(map.point(tracer.time, tracer.progress))
                        .opacity(tracer.opacity)
                        .allowsHitTesting(false)
                }
                handle(0, at: map.point(curve.x1, curve.y1), map: map)
                handle(1, at: map.point(curve.x2, curve.y2), map: map)
            }
            .coordinateSpace(.named("graph"))
        }
        .aspectRatio(1, contentMode: .fit)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke).allowsHitTesting(false))
    }

    private func draw(in ctx: inout GraphicsContext, map: GraphMapping) {
        let t = Self.time, pr = Self.progress
        let box = CGRect(from: map.point(t.lowerBound, pr.upperBound), to: map.point(t.upperBound, pr.lowerBound))
        let unit = CGRect(from: map.point(0, 1), to: map.point(1, 0))
        ctx.fill(Path(roundedRect: box, cornerRadius: 4), with: .color(.white.opacity(0.025)))
        ctx.fill(Path(unit), with: .color(.white.opacity(0.03)))
        var grid = Path()
        for v in [0.25, 0.5, 0.75] {
            grid.move(to: map.point(v, pr.lowerBound)); grid.addLine(to: map.point(v, pr.upperBound))
        }
        for v in stride(from: pr.lowerBound + 0.25, to: pr.upperBound, by: 0.25) where v != 0 && v != 1 {
            grid.move(to: map.point(0, v)); grid.addLine(to: map.point(1, v))
        }
        ctx.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 1)
        var bounds = Path()
        bounds.move(to: map.point(0, 0)); bounds.addLine(to: map.point(1, 0))
        bounds.move(to: map.point(0, 1)); bounds.addLine(to: map.point(1, 1))
        ctx.stroke(bounds, with: .color(.white.opacity(0.14)), lineWidth: 1)
        ctx.stroke(Path(roundedRect: box, cornerRadius: 4), with: .color(.white.opacity(0.08)), lineWidth: 1)

        var linear = Path()
        linear.move(to: map.point(0, 0)); linear.addLine(to: map.point(1, 1))
        ctx.stroke(linear, with: .color(.white.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
        var arms = Path()
        arms.move(to: map.point(0, 0)); arms.addLine(to: map.point(curve.x1, curve.y1))
        arms.move(to: map.point(1, 1)); arms.addLine(to: map.point(curve.x2, curve.y2))
        ctx.stroke(arms, with: .color(.white.opacity(0.35)), lineWidth: 1.5)
        var path = Path()
        path.move(to: map.point(0, 0))
        path.addCurve(to: map.point(1, 1), control1: map.point(curve.x1, curve.y1), control2: map.point(curve.x2, curve.y2))
        ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        for end in [map.point(0, 0), map.point(1, 1)] {
            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 3, y: end.y - 3, width: 6, height: 6)), with: .color(.white))
        }
    }

    private func handle(_ index: Int, at point: CGPoint, map: GraphMapping) -> some View {
        let (t, p) = index == 0 ? (curve.x1, curve.y1) : (curve.x2, curve.y2)
        let active = dragging == index
        return Circle()
            .fill(Theme.panel)
            .overlay(Circle().strokeBorder(.white, lineWidth: 2))
            .frame(width: 14, height: 14)
            .scaleEffect(active ? 1.15 : 1)
            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2).frame(width: 22, height: 22)
                .opacity(focused == index ? 1 : 0))
            .frame(width: 30, height: 30)
            .contentShape(Circle())
            .position(point)
            .focusable()
            .focusEffectDisabled()
            .focused($focused, equals: index)
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("graph"))
                .onChanged { value in
                    dragging = index
                    focused = index
                    let (t, p) = map.value(at: value.location)
                    set(index, t, p)
                }
                .onEnded { _ in dragging = nil })
            .onKeyPress(phases: [.down, .repeat]) { press in
                let step = press.modifiers.contains(.shift) ? Self.bigStep : Self.step
                let delta: (Double, Double)
                switch press.key {
                case .leftArrow: delta = (-step, 0)
                case .rightArrow: delta = (step, 0)
                case .upArrow: delta = (0, step)
                case .downArrow: delta = (0, -step)
                default: return .ignored
                }
                set(index, t + delta.0, p + delta.1)
                return .handled
            }
            .pointerStyle(active ? .grabActive : .grabIdle)
            .animation(Theme.press, value: active)
            .help("Drag to shape the motion. Higher means further along sooner.")
            .accessibilityLabel("Control point \(index + 1)")
            .accessibilityValue("time \(Self.number(t)), progress \(Self.number(p))")
    }

    private func set(_ index: Int, _ t: Double, _ p: Double) {
        let t = (min(max(t, 0), 1) / Self.step).rounded() * Self.step
        let p = (min(max(p, Self.progress.lowerBound), Self.progress.upperBound) / Self.step).rounded() * Self.step
        var next = curve
        if index == 0 { next.x1 = t; next.y1 = p } else { next.x2 = t; next.y2 = p }
        if next != curve { curve = next }
    }

    static func number(_ v: Double) -> String {
        let r = (v * 1000).rounded() / 1000
        return r == r.rounded() ? String(Int(r)) : String(r)
    }
}

private struct GraphMapping {
    static let inset: CGFloat = 16
    let size: CGSize

    private var plot: CGSize { CGSize(width: max(size.width - 2 * Self.inset, 1), height: max(size.height - 2 * Self.inset, 1)) }

    func point(_ t: Double, _ p: Double) -> CGPoint {
        let tr = CurveGraph.time, pr = CurveGraph.progress
        return CGPoint(x: Self.inset + (t - tr.lowerBound) / (tr.upperBound - tr.lowerBound) * plot.width,
                       y: Self.inset + (pr.upperBound - p) / (pr.upperBound - pr.lowerBound) * plot.height)
    }

    func value(at point: CGPoint) -> (Double, Double) {
        let tr = CurveGraph.time, pr = CurveGraph.progress
        return (tr.lowerBound + (point.x - Self.inset) / plot.width * (tr.upperBound - tr.lowerBound),
                pr.upperBound - (point.y - Self.inset) / plot.height * (pr.upperBound - pr.lowerBound))
    }
}

private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }

private extension CGRect {
    init(from a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
}
