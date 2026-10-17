//
//  TimelineBlocks.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import SliceCore
import SwiftUI

struct BlockView<Detail: View>: View {
    let title: String
    let color: Color
    let start: Double
    let end: Double
    let pps: CGFloat
    let height: CGFloat
    let selected: Bool
    let select: () -> Void
    let setRange: (Double, Double) -> Void
    /// A thin block sharing its lane with others at the same time: just the detail, smaller.
    var compact = false
    @ViewBuilder var detail: Detail

    @State private var origin: (Double, Double)?
    @State private var hovering = false

    var body: some View {
        let width = max((end - start) * pps, 6)
        let lit = hovering || selected
        let radius: CGFloat = compact ? 6 : 10
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(lit ? 1 : 0.9), color.opacity(lit ? 0.82 : 0.7)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.9 : hovering ? 0.3 : 0.12), lineWidth: selected ? 2 : 1))
            .overlay {
                if compact {
                    if width > 50 {
                        detail.font(.rounded(10)).foregroundStyle(.white).labelStyle(.titleAndIcon)
                            .lineLimit(1)
                            .padding(.horizontal, 8)
                            .allowsHitTesting(false)
                    }
                } else if width > 70 {
                    VStack(spacing: 0) {
                        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.5))
                        detail.font(.rounded(12)).foregroundStyle(.white).labelStyle(.titleAndIcon)
                    }
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .leading) { handle(edge: .leading) }
            .overlay(alignment: .trailing) { handle(edge: .trailing) }
            .frame(width: width, height: height)
            .shadow(color: color.opacity(lit ? 0.45 : 0), radius: 8, y: 2)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.hover, value: selected)
            .offset(x: start * pps)
            .onTapGesture { select() }
            .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { v in
                    if origin == nil {
                        origin = (start, end)
                        select()
                    }
                    let dt = v.translation.width / pps
                    setRange(origin!.0 + dt, origin!.1 + dt)
                }
                .onEnded { _ in origin = nil })
    }

    private func handle(edge: HorizontalEdge) -> some View {
        EdgeHandle(visible: hovering || selected) { dx in
            if origin == nil {
                origin = (start, end)
                select()
            }
            let dt = dx / pps
            if edge == .leading {
                setRange(origin!.0 + dt, origin!.1)
            } else {
                setRange(origin!.0, origin!.1 + dt)
            }
        } onEnded: { origin = nil }
    }
}

struct Ruler: View {
    let duration: Double
    let pps: CGFloat

    static func step(pps: CGFloat) -> Double {
        let steps: [Double] = [0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300]
        return steps.first { $0 * pps >= 90 } ?? 600
    }

    var body: some View {
        Canvas { ctx, size in
            let step = Self.step(pps: pps)
            let dotY = size.height - 5
            var t = 0.0
            while t <= duration + 0.001 {
                let x = t * pps
                if t > 0 {
                    ctx.draw(Text(rulerLabel(t)).font(.rounded(10).monospacedDigit()).foregroundColor(.secondary),
                             at: CGPoint(x: x, y: 2), anchor: .top)
                }
                dot(ctx, x: x, y: dotY, r: 1.5, opacity: 0.45)
                let half = x + step * pps / 2
                if t + step / 2 <= duration { dot(ctx, x: half, y: dotY, r: 1.2, opacity: 0.25) }
                t += step
            }
        }
    }

    private func dot(_ ctx: GraphicsContext, x: CGFloat, y: CGFloat, r: CGFloat, opacity: Double) {
        ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(.white.opacity(opacity)))
    }

    private func rulerLabel(_ t: Double) -> String {
        t < 60 && t.truncatingRemainder(dividingBy: 1) != 0 ? String(format: "%.1fs", t) : String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
