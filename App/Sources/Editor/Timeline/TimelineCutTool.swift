//
//  TimelineCutTool.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import AppKit
import SliceCore
import SwiftUI

enum ScissorsPointer {
    static let style = PointerStyle.image(Image(nsImage: image), hotSpot: .center)

    private static let image: NSImage = {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
        guard let symbol = NSImage(systemSymbolName: "scissors", accessibilityDescription: "Cut")?
            .withSymbolConfiguration(config) else { return NSImage() }
        let fill = tinted(symbol, .white), outline = tinted(symbol, NSColor.black.withAlphaComponent(0.85))
        return NSImage(size: NSSize(width: 24, height: 30), flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Upright, blades up, so the pivot sits on the hotspot's vertical line.
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: .pi / 2)
            let s = symbol.size, base = NSRect(x: -s.width / 2, y: -s.height / 2, width: s.width, height: s.height)
            for a in stride(from: 0.0, to: 2 * .pi, by: .pi / 6) {
                outline.draw(in: base.offsetBy(dx: cos(a) * 1.3, dy: sin(a) * 1.3))
            }
            fill.draw(in: base)
            return true
        }
    }()

    private static func tinted(_ symbol: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

struct CutLayer: View {
    let segments: [Segment]
    let pps: CGFloat
    let height: CGFloat
    let playhead: () -> Double
    let cut: (Double) -> Void

    @State private var time: Double?
    @State private var snapped = false

    var body: some View {
        let target = time.flatMap { t in Self.canSplit(segments, at: t) ? t : nil }
        Rectangle()
            .fill(Color.white.opacity(0.0001))
            .overlay(alignment: .topLeading) {
                if let target {
                    CutGuide(time: target, height: height)
                        .offset(x: target * pps - CutGuide.width / 2)
                        .transition(.opacity)
                }
            }
            .animation(Theme.hover, value: target == nil)
            .frame(height: height)
            .contentShape(Rectangle())
            .pointerStyle(ScissorsPointer.style)
            .onContinuousHover { phase in
                switch phase {
                case let .active(p): hover(at: p.x)
                case .ended: time = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { v in
                let t = time ?? v.location.x / pps
                guard Self.canSplit(segments, at: t) else { return }
                cut(t)
            })
            .help("Click to split the clip here. Esc to stop cutting")
    }

    private func hover(at x: CGFloat) {
        let head = playhead()
        let snap = abs(x - head * pps) < 6
        if snap, !snapped { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
        snapped = snap
        time = snap ? head : max(x / pps, 0)
    }

    static func canSplit(_ segments: [Segment], at t: Double) -> Bool {
        let m = Project.minSplitMargin
        return segments.contains { t > $0.editedStart + m && t < $0.editedEnd - m }
    }
}

struct CutGuide: View {
    static let width: CGFloat = 64
    let time: Double
    let height: CGFloat

    var body: some View {
        VStack(spacing: 3) {
            Text(format(time))
                .font(.rounded(10).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Capsule().fill(Theme.panel))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .fixedSize()
            Capsule()
                .fill(Color.white)
                .frame(width: 2, height: height + 6)
                .shadow(color: .black.opacity(0.55), radius: 2)
        }
        .frame(width: Self.width)
        .offset(y: -22)
        .allowsHitTesting(false)
    }
}

struct CutFlashMark: View {
    let height: CGFloat
    @State private var done = false

    var body: some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 2, height: height + 6)
            .shadow(color: .white.opacity(0.9), radius: done ? 10 : 3)
            .scaleEffect(x: done ? 2 : 1, y: done ? 0.7 : 1)
            .opacity(done ? 0 : 1)
            .offset(y: -3)
            .allowsHitTesting(false)
            .onAppear { withAnimation(.smooth(duration: 0.45)) { done = true } }
    }
}
