//
//  AnnotationBoxOverlay.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import SliceCore
import SwiftUI

/// The selected drawing's box over the unzoomed preview: drag inside to move it, drag a corner to resize it.
struct AnnotationBoxOverlay: View {
    @ObservedObject var editor: EditorModel
    let block: AnnotationBlock
    let viewSize: CGSize
    @State private var origin: CGRect?

    private enum Corner: CaseIterable { case topLeft, topRight, bottomLeft, bottomRight }

    /// Room around the strokes, which also gives a straight line a box to grab.
    private static let margin: CGFloat = 8

    private var content: CGRect {
        let project = editor.project
        let i = project.clipStarts.lastIndex { $0 <= editor.time } ?? 0
        let clip = project.clips[safe: i]
        let g = ScreenGeometry(contentSize: clip?.screenPixelSize ?? editor.previewSize, output: editor.previewSize,
                               style: project.style, shapedByAlpha: clip?.device != nil)
        let k = viewSize.width / editor.previewSize.width
        let c = g.contentRect
        return CGRect(x: c.minX * k, y: c.minY * k, width: c.width * k, height: c.height * k)
    }

    var body: some View {
        let c = content
        let points = editor.screenPoints(for: block)
        let r = block.bounds(screenPoints: points)
        let box = CGRect(x: c.minX + r.minX * c.width, y: c.minY + r.minY * c.height, width: r.width * c.width,
                         height: r.height * c.height).insetBy(dx: -Self.margin, dy: -Self.margin)
        let shape = RoundedRectangle(cornerRadius: 6, style: .continuous)
        ZStack(alignment: .topLeading) {
            shape
                .fill(Color.white.opacity(0.04))
                .overlay(shape.strokeBorder(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 1.5, dash: [5, 3])))
                .frame(width: box.width, height: box.height)
                .contentShape(shape)
                .pointerStyle(origin == nil ? .grabIdle : .grabActive)
                .offset(x: box.minX, y: box.minY)
                .gesture(drag(r, content: c, points: points) { start, dx, dy in start.offsetBy(dx: dx, dy: dy) })
            ForEach(Corner.allCases, id: \.self) { corner in
                handle(corner)
                    .offset(x: (corner == .topLeft || corner == .bottomLeft ? box.minX : box.maxX) - 6,
                            y: (corner == .topLeft || corner == .topRight ? box.minY : box.maxY) - 6)
                    .gesture(drag(r, content: c, points: points) { start, dx, dy in
                        Self.resized(start, corner: corner, dx: dx, dy: dy, keepsAspect: block.mark.tool == .text)
                    })
            }
        }
        .frame(width: viewSize.width, height: viewSize.height, alignment: .topLeading)
        .accessibilityLabel("Drawing")
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

    private func drag(_ current: CGRect, content c: CGRect, points: CGSize,
                      _ change: @escaping (CGRect, Double, Double) -> CGRect) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { v in
                let start = origin ?? current
                if origin == nil { origin = start }
                let rect = change(start, v.translation.width / max(c.width, 1), v.translation.height / max(c.height, 1))
                editor.updateAnnotation(block.id) { $0.fit(to: rect, screenPoints: points) }
            }
            .onEnded { _ in origin = nil }
    }

    /// A side the mark has no extent along (a level line) stays that way; a label keeps its shape as it grows.
    private static func resized(_ r: CGRect, corner: Corner, dx: Double, dy: Double, keepsAspect: Bool) -> CGRect {
        let m = 0.005
        let left = corner == .topLeft || corner == .bottomLeft, top = corner == .topLeft || corner == .topRight
        var w = r.width > 0 ? max(r.width + (left ? -dx : dx), m) : 0
        var h = r.height > 0 ? max(r.height + (top ? -dy : dy), m) : 0
        if keepsAspect, r.width > 0, r.height > 0 {
            let k = max(w / r.width, h / r.height)
            (w, h) = (r.width * k, r.height * k)
        }
        return CGRect(x: left ? r.maxX - w : r.minX, y: top ? r.maxY - h : r.minY, width: w, height: h)
    }
}

/// Click a drawing in the preview to select it, or beside it to let it go. Nothing here runs until a click: what's
/// under it is worked out then, so scrubbing, playing and editing never pay for it.
struct AnnotationTapCatcher: View {
    @ObservedObject var editor: EditorModel
    let viewSize: CGSize

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { select(at: $0.location) })
    }

    private func select(at p: CGPoint) {
        guard !editor.isPlaying else { return }
        let t = editor.time
        let active = editor.project.annotations(at: t).filter { $0.drawnCount(at: t) > 0 }
        let (g, view) = placement(at: t)
        let k = viewSize.width / max(view.width, 1)
        let c = g.contentRect
        let hit = active.last { b in
            let r = b.bounds(screenPoints: editor.screenPoints(for: b))
            return CGRect(x: (c.minX + r.minX * c.width - view.minX) * k, y: (c.minY + r.minY * c.height - view.minY) * k,
                          width: r.width * c.width * k, height: r.height * c.height * k).insetBy(dx: -8, dy: -8).contains(p)
        }
        if let hit {
            editor.selection = .annotation(hit.id)
        } else if editor.selectedAnnotation != nil {
            editor.selection = nil
        }
    }

    /// Where the screen sits and what part of the frame shows: the whole frame while a drawing's being edited, else
    /// the zoom at `t` from a scene made just for this click, leaving the preview's own untouched.
    private func placement(at t: Double) -> (ScreenGeometry, CGRect) {
        if editor.isEditingAnnotation {
            let project = editor.project
            let clip = project.clips[safe: project.clipStarts.lastIndex { $0 <= t } ?? 0]
            let g = ScreenGeometry(contentSize: clip?.screenPixelSize ?? editor.previewSize, output: editor.previewSize,
                                   style: project.style, shapedByAlpha: clip?.device != nil)
            return (g, g.fullView)
        }
        let scene = RenderScene(project: editor.project, output: editor.previewSize, cursor: editor.cursorTrack)
        return (scene.geometry(at: t), scene.view(at: t))
    }
}
