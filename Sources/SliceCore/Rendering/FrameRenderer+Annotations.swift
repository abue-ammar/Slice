//
//  FrameRenderer+Annotations.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/20/26.
//

import CoreImage
import CoreVideo

extension FrameRenderer {
    /// The screen with the timeline's annotations drawn over it, before it's framed, so they ride along with zooms.
    /// Each finished mark is drawn once, at the size the frame needs, and kept until it's edited; only a mark still
    /// drawing itself in is drawn again each frame.
    func annotated(_ screen: CIImage, scene: RenderScene, time t: Double) -> CIImage {
        let blocks = scene.project.annotations
        guard !blocks.isEmpty else { return screen }
        let i = scene.clipIndex(at: t)
        let e = screen.extent
        guard scene.project.clips.indices.contains(i), scene.project.clips[i].device == nil, !e.isInfinite, e.width > 0,
              scene.project.clips[i].captureRect.width > 0 else { return screen }
        let active = blocks.filter { $0.isActive(at: t) }
        guard !active.isEmpty else { return screen }
        let scale = e.width / scene.project.clips[i].captureRect.width
        let r = annotationRasterScale(scene: scene, time: t, screen: e)
        var image = screen
        for b in active {
            let n = b.drawnCount(at: t)
            guard n > 0 else { continue }
            let layer: CIImage?
            if n >= b.mark.points.count {
                if let kept = annotationMarks.image(for: b.mark, screen: e.size, scale: r) {
                    layer = kept
                } else {
                    layer = markLayer(b.mark, count: n, scale: scale, raster: r, in: e)
                    if let layer { annotationMarks.keep(layer, for: b.mark, screen: e.size, scale: r) }
                }
            } else {
                layer = markLayer(b.mark, count: n, scale: scale, raster: r, in: e)
            }
            if let layer { image = layer.composited(over: image) }
        }
        return image.cropped(to: e)
    }

    /// How finely to draw marks, as a fraction of the screen's pixels: as fine as the frame shows the screen at its
    /// closest now, in steps so a zoom doesn't draw them again every frame. The preview needs far fewer pixels than
    /// the recording has; an export at full size gets them all.
    func annotationRasterScale(scene: RenderScene, time t: Double, screen e: CGRect) -> CGFloat {
        let content = scene.geometry(at: t).contentRect.width
        let view = scene.view(at: t).width
        let lens = scene.lens(at: t)?.magnification ?? 1
        let shown = content * scene.output.width / max(view, 1) * CGFloat(max(lens, 1))
        let raw = min(max(shown / e.width, 1.0 / 16), 1)
        return min(pow(2, (log2(raw) * 2).rounded(.up) / 2), 1)
    }

    /// One mark drawn into memory the GPU reads directly, so showing it each frame doesn't copy it up again.
    func markLayer(_ a: Annotation, count n: Int, scale: CGFloat, raster r: CGFloat, in e: CGRect) -> CIImage? {
        let place: (CGPoint) -> CGPoint = { CGPoint(x: e.minX + $0.x * e.width, y: e.minY + (1 - $0.y) * e.height) }
        let box = AnnotationPainter.bounds(of: a, count: n, scale: scale, place: place).intersection(e)
        guard !box.isNull, box.width >= 1, box.height >= 1 else { return nil }
        let ox = (box.minX * r).rounded(.down), oy = (box.minY * r).rounded(.down)
        let w = Int((box.maxX * r).rounded(.up) - ox), h = Int((box.maxY * r).rounded(.up) - oy)
        guard w > 0, h > 0 else { return nil }
        var buffer: CVPixelBuffer?
        let attributes: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
                                         kCVPixelBufferMetalCompatibilityKey as String: true]
        guard CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: Self.annotationSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: -ox, y: -oy)
        ctx.scaleBy(x: r, y: r)
        AnnotationPainter.draw(a, count: n, in: ctx, scale: scale, place: place)
        return CIImage(cvPixelBuffer: buffer, options: [.colorSpace: Self.annotationSpace])
            .transformed(by: CGAffineTransform(translationX: ox, y: oy).concatenating(CGAffineTransform(scaleX: 1 / r, y: 1 / r)))
    }

    static let annotationSpace = CGColorSpace(name: CGColorSpace.sRGB)!
}

/// Finished marks as drawn, by mark. A mark that hasn't been edited shares its points with the one kept, so telling
/// it's unchanged costs nothing; an edited one is drawn again.
final class AnnotationMarkCache: @unchecked Sendable {
    private struct Entry {
        let mark: Annotation
        let screen: CGSize
        let scale: CGFloat
        let image: CIImage
    }

    private let lock = NSLock()
    private var entries: [UUID: Entry] = [:]

    func image(for mark: Annotation, screen: CGSize, scale: CGFloat) -> CIImage? {
        lock.withLock {
            guard let e = entries[mark.id], e.screen == screen, e.scale >= scale, e.mark == mark else { return nil }
            return e.image
        }
    }

    func keep(_ image: CIImage, for mark: Annotation, screen: CGSize, scale: CGFloat) {
        lock.withLock {
            if entries.count > 512 { entries.removeAll() }
            entries[mark.id] = Entry(mark: mark, screen: screen, scale: scale, image: image)
        }
    }
}
