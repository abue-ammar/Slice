//
//  SpotlightOverlay.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import SliceCore
import SwiftUI

/// The selected spotlight's circle over the unzoomed preview: drag inside to move it, drag its edge to resize.
struct SpotlightOverlay: View {
    @ObservedObject var editor: EditorModel
    let block: SpotlightBlock
    let viewSize: CGSize
    @State private var origin: CGPoint?
    @State private var resizing = false

    static let sizes: ClosedRange<Double> = 0.5 ... 2.5

    private var layout: (content: CGRect, unit: CGFloat) {
        let project = editor.project
        let i = project.clipStarts.lastIndex { $0 <= editor.time } ?? 0
        let clip = project.clips.indices.contains(i) ? project.clips[i] : nil
        let g = ScreenGeometry(contentSize: clip?.screenPixelSize ?? editor.previewSize, output: editor.previewSize,
                               style: project.style, shapedByAlpha: clip?.device != nil)
        let k = viewSize.width / editor.previewSize.width
        let c = g.contentRect
        let content = CGRect(x: c.minX * k, y: c.minY * k, width: c.width * k, height: c.height * k)
        let points = (clip?.captureRect.width ?? 0) > 0 ? clip!.captureRect.width : 1440
        return (content, ClickSpotlight.radius * content.width / points)
    }

    var body: some View {
        let (c, unit) = layout
        let center = CGPoint(x: c.minX + block.center.x * c.width, y: c.minY + block.center.y * c.height)
        let r = unit * block.size
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.white.opacity(0.04))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                .frame(width: r * 2, height: r * 2)
                .contentShape(Circle())
                .pointerStyle(origin == nil ? .grabIdle : .grabActive)
                .offset(x: center.x - r, y: center.y - r)
                .gesture(move(content: c))
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
                .offset(x: center.x - 3, y: center.y - 3)
                .allowsHitTesting(false)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                .contentShape(Rectangle().inset(by: -6))
                .pointerStyle(.frameResize(position: .trailing))
                .offset(x: center.x + r - 6, y: center.y - 6)
                .gesture(resize(center: center, unit: unit))
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        .accessibilityLabel("Spotlight circle")
    }

    private func move(content c: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let start = origin ?? block.center
                if origin == nil { origin = start }
                let p = CGPoint(x: start.x + v.translation.width / max(c.width, 1), y: start.y + v.translation.height / max(c.height, 1))
                editor.updateSpotlight(block.id) { $0.center = p }
            }
            .onEnded { _ in origin = nil }
    }

    private func resize(center: CGPoint, unit: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let d = hypot(v.location.x - center.x, v.location.y - center.y)
                let size = min(max(Double(d / max(unit, 1)), Self.sizes.lowerBound), Self.sizes.upperBound)
                editor.updateSpotlight(block.id) { $0.size = size }
            }
    }
}
