//
//  RedactBoxOverlay.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import SliceCore
import SwiftUI

/// The selected blur's box over the unzoomed preview: drag inside to move it, drag a corner to resize.
struct RedactBoxOverlay: View {
    @ObservedObject var editor: EditorModel
    let block: RedactBlock
    let viewSize: CGSize
    @State private var origin: CGRect?

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    private var content: CGRect {
        let project = editor.project
        let i = project.clipStarts.lastIndex { $0 <= editor.time } ?? 0
        let clip = project.clips.indices.contains(i) ? project.clips[i] : nil
        let g = ScreenGeometry(contentSize: clip?.screenPixelSize ?? editor.previewSize, output: editor.previewSize,
                               style: project.style, shapedByAlpha: clip?.device != nil)
        let k = viewSize.width / editor.previewSize.width
        let c = g.contentRect
        return CGRect(x: c.minX * k, y: c.minY * k, width: c.width * k, height: c.height * k)
    }

    var body: some View {
        let c = content
        let r = block.rect
        let box = CGRect(x: c.minX + r.minX * c.width, y: c.minY + r.minY * c.height, width: r.width * c.width, height: r.height * c.height)
        let shape = RoundedRectangle(cornerRadius: min(box.width, box.height) * 0.18, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape
                .fill(Color.white.opacity(0.06))
                .overlay(shape.strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                .frame(width: box.width, height: box.height)
                .contentShape(shape)
                .pointerStyle(origin == nil ? .grabIdle : .grabActive)
                .offset(x: box.minX, y: box.minY)
                .gesture(drag(content: c) { start, dx, dy in start.offsetBy(dx: dx, dy: dy) })
            ForEach(Corner.allCases, id: \.self) { corner in
                handle(corner)
                    .offset(x: (corner == .topLeft || corner == .bottomLeft ? box.minX : box.maxX) - 6,
                            y: (corner == .topLeft || corner == .topRight ? box.minY : box.maxY) - 6)
                    .gesture(drag(content: c) { start, dx, dy in resized(start, corner: corner, dx: dx, dy: dy) })
            }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        .accessibilityLabel("Blur box")
    }

    private func handle(_ corner: Corner) -> some View {
        let position: FrameResizePosition = switch corner {
        case .topLeft: .topLeading
        case .topRight: .topTrailing
        case .bottomLeft: .bottomLeading
        case .bottomRight: .bottomTrailing
        }
        return RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Color.white)
            .frame(width: 12, height: 12)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .contentShape(Rectangle().inset(by: -6))
            .pointerStyle(.frameResize(position: position))
    }

    private func drag(content c: CGRect, _ change: @escaping (CGRect, Double, Double) -> CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let start = origin ?? block.rect
                if origin == nil { origin = start }
                let rect = change(start, v.translation.width / max(c.width, 1), v.translation.height / max(c.height, 1))
                editor.updateRedaction(block.id) { $0.rect = rect }
            }
            .onEnded { _ in origin = nil }
    }

    private func resized(_ r: CGRect, corner: Corner, dx: Double, dy: Double) -> CGRect {
        let m = RedactBlock.minSize * 2
        var (x0, y0, x1, y1) = (r.minX, r.minY, r.maxX, r.maxY)
        switch corner {
        case .topLeft: (x0, y0) = (min(x0 + dx, x1 - m), min(y0 + dy, y1 - m))
        case .topRight: (x1, y0) = (max(x1 + dx, x0 + m), min(y0 + dy, y1 - m))
        case .bottomLeft: (x0, y1) = (min(x0 + dx, x1 - m), max(y1 + dy, y0 + m))
        case .bottomRight: (x1, y1) = (max(x1 + dx, x0 + m), max(y1 + dy, y0 + m))
        }
        (x0, y0, x1, y1) = (max(x0, 0), max(y0, 0), min(x1, 1), min(y1, 1))
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
