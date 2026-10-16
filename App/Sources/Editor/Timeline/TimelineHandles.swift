//
//  TimelineHandles.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import SliceCore
import SwiftUI

struct PinShape: Shape {
    func path(in rect: CGRect) -> Path {
        let r = rect.width / 2
        let centre = CGPoint(x: rect.midX, y: rect.minY + r)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        let theta = acos(r / max(tip.y - centre.y, r + 0.01))
        var p = Path()
        p.move(to: tip)
        p.addArc(center: centre, radius: r, startAngle: .radians(.pi / 2 + theta), endAngle: .radians(.pi / 2 - theta), clockwise: false)
        p.closeSubpath()
        return p
    }
}

struct CutPin: View {
    static let width: CGFloat = 32
    static let height: CGFloat = 38
    let removed: Double?
    let live: Bool

    var body: some View {
        VStack(spacing: 0) {
            if let removed {
                Text(Self.label(removed, precise: live))
                    .font(.rounded(8.5, .heavy).monospacedDigit())
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(value: removed))
            }
            Image(systemName: "scissors").font(.system(size: removed == nil ? 11 : 8, weight: .bold))
        }
        .lineLimit(1)
        .foregroundStyle(Color.black.opacity(0.8))
        .padding(.horizontal, 5)
        .padding(.top, 2)
        .frame(width: Self.width, height: Self.width)
        .frame(height: Self.height, alignment: .top)
        .background {
            PinShape()
                .fill(LinearGradient(colors: [Color(red: 1, green: 0.78, blue: 0.34), Theme.clip], startPoint: .top, endPoint: .bottom))
                .overlay(PinShape().stroke(Color.white.opacity(live ? 0.9 : 0.3), lineWidth: 1))
        }
        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
        .scaleEffect(live ? 1.1 : 1, anchor: .bottom)
        .contentShape(PinShape())
        .animation(Theme.hover, value: live)
    }

    static func label(_ s: Double, precise: Bool) -> String {
        if precise || (s < 10 && abs(s - s.rounded()) >= 0.05) { return String(format: "%.1fs", s) }
        if s < 60 { return String(format: "%.0fs", s) }
        return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }
}

struct TrimDrag: Equatable {
    var segment: Segment
    var leading: Bool
    var delta: Double

    var edgeTime: Double { (leading ? segment.editedStart : segment.editedEnd) + delta }

    var removedRange: ClosedRange<Double>? {
        if leading, delta > 0 { return segment.editedStart ... segment.editedStart + delta }
        if !leading, delta < 0 { return segment.editedEnd + delta ... segment.editedEnd }
        return nil
    }
}

struct TrimGhost: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Canvas { ctx, size in
            var x = -size.height
            while x < size.width {
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                ctx.stroke(p, with: .color(Theme.clip.opacity(0.22)), lineWidth: 1.5)
                x += 7
            }
        }
        .background(shape.fill(Theme.clip.opacity(0.06)))
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.clip.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        .allowsHitTesting(false)
    }
}

struct EdgeHandle: View {
    let visible: Bool
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(visible ? 0.9 : 0))
            .frame(width: 3, height: 20)
            .frame(width: 10)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { onChanged($0.translation.width) }
                .onEnded { _ in onEnded() })
    }
}
