//
//  FrameRenderer+Cursor.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/13/26.
//

import CoreImage

extension FrameRenderer {
    func cursorLayer(_ pointer: CursorPointer, geometry g: ScreenGeometry, views: [CGRect], viewShutter: Double,
                     settings: CursorSettings, press: CGFloat, output: CGSize, canvas: CGRect) -> CIImage? {
        let content = viewed(g.contentRect, view: views[0], output: output)
        let size = settings.size * press
        let scale = content.width / pointer.screenPoints.width * size
        guard scale.isFinite, scale > 0.05 else { return nil }
        let steps = 8.0
        let raster = CGFloat(pow(2, (log2(Double(scale)) * steps).rounded(.up) / steps))
        func sprite(_ type: CursorType) -> CursorSprite? {
            let shape = settings.style.followsSystemCursor ? type.rawValue : ""
            let key = "\(settings.style.rawValue)|\(shape)|\(raster)" as NSString
            if let cached = cursorSprites.object(forKey: key) { return cached }
            guard let made = CursorSprite.render(style: settings.style, type: type, scale: raster) else { return nil }
            cursorSprites.setObject(made, forKey: key)
            return made
        }
        guard let current = sprite(pointer.type) else { return nil }
        let previous = pointer.fade < 1 ? pointer.previousType.flatMap(sprite) : nil
        func placed(_ s: CursorSprite, _ pose: CursorPose, _ content: CGRect) -> CIImage {
            let hot = CGPoint(x: content.minX + pose.position.x * content.width,
                              y: output.height - (content.minY + pose.position.y * content.height))
            let f = content.width / pointer.screenPoints.width * size / raster
            return s.image.transformed(by: CGAffineTransform(translationX: -s.hotspot.x, y: -s.hotspot.y)
                .concatenating(CGAffineTransform(scaleX: f, y: f))
                .concatenating(CGAffineTransform(rotationAngle: CGFloat(pose.angle)))
                .concatenating(CGAffineTransform(translationX: hot.x, y: hot.y)))
        }
        func drawn(_ pose: CursorPose, _ content: CGRect) -> CIImage {
            let now = placed(current, pose, content)
            guard let previous else { return now }
            return scaleAlpha(now, by: pointer.fade).applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: scaleAlpha(placed(previous, pose, content), by: 1 - pointer.fade),
            ])
        }
        func contentRect(age: Double) -> CGRect {
            guard views.count > 1, viewShutter > 0 else { return content }
            let u = min(max(age / viewShutter, 0), 1) * Double(views.count - 1)
            let i = min(Int(u), views.count - 2)
            return viewed(g.contentRect, view: lerp(views[i], views[i + 1], u - Double(i)), output: output)
        }
        var layer: CIImage
        let n = pointer.trail.count
        if n > 1 {
            layer = average(pointer.trail.enumerated().map { i, pose in
                drawn(pose, contentRect(age: pointer.shutter * Double(n - 1 - i) / Double(n - 1)))
            })
        } else {
            layer = drawn(pointer.pose, content)
        }
        if pointer.opacity < 1 { layer = scaleAlpha(layer, by: pointer.opacity) }
        let visible = flip(content, height: output.height).intersection(canvas)
        guard layer.extent.intersects(visible) else { return nil }
        return layer.cropped(to: visible)
    }

    // MARK: - 3D tilt

    static let tiltKernel = kernel("screenTilt", in: "ScreenTilt", label: "Screen tilt")

    func tilted(_ layer: CIImage, by warp: Homography, output: CGSize) -> CIImage {
        guard let kernel = Self.tiltKernel, let inverse = warp.inverse else { return layer }
        let m = inverse.m.map { CGFloat($0) }
        let source = layer.extent
        let args: [Any] = [layer, CIVector(x: m[0], y: m[1], z: m[2]), CIVector(x: m[3], y: m[4], z: m[5]),
                           CIVector(x: m[6], y: m[7], z: m[8])]
        return kernel.apply(extent: CGRect(origin: .zero, size: output), roiCallback: { _, r in
            guard let back = inverse.bounds(of: r) else { return source }
            return back.insetBy(dx: -3, dy: -3).intersection(source)
        }, arguments: args) ?? layer
    }
}
