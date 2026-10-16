//
//  FrameRenderer+Keystrokes.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/13/26.
//

import AppKit
import CoreImage
import CoreText

extension FrameRenderer {
    func keystrokeLayer(scene: RenderScene, time t: Double, avoiding camera: CGRect?, output: CGSize,
                        clearance: () -> CGFloat) -> CIImage? {
        let states = scene.keystrokes.states(at: t)
        guard !states.isEmpty else { return nil }
        let settings = scene.project.keystrokes
        let fontSize = (min(output.width, output.height) * settings.size).rounded()
        guard fontSize >= 4 else { return nil }
        let lift = clearance()
        var layer: CIImage?
        for state in states where state.opacity > 0.002 {
            let key = "\(state.label)|\(state.count)|\(fontSize)" as NSString
            let cap: CIImage
            if let cached = keycapCache.object(forKey: key) {
                cap = cached
            } else {
                guard let made = Self.keycapImage(state.label, count: state.count, fontSize: fontSize) else { continue }
                keycapCache.setObject(made, forKey: key)
                cap = made
            }
            let size = cap.extent.insetBy(dx: Self.keycapMargin(fontSize), dy: Self.keycapMargin(fontSize)).size
            let rect = Self.keycapRect(size: size, position: settings.position, clearance: lift, camera: camera, output: output)

            var image = cap
            if state.blur > 0.002 {
                let sigma = state.blur * Double(fontSize) * 0.34
                image = image.applyingGaussianBlur(sigma: sigma).cropped(to: cap.extent.insetBy(dx: -3 * sigma, dy: -3 * sigma))
            }
            if state.opacity < 0.998 { image = scaleAlpha(image, by: state.opacity) }
            if abs(state.scale - 1) > 0.0005 {
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                image = image.transformed(by: CGAffineTransform(translationX: -c.x, y: -c.y)
                    .concatenating(CGAffineTransform(scaleX: state.scale, y: state.scale))
                    .concatenating(CGAffineTransform(translationX: c.x, y: c.y)))
            }
            var drop = state.drop * size.height
            if lift > 0, settings.position == .bottom {
                drop = min(drop, CaptionMetrics(settings: scene.project.subtitles, output: output).gap * 0.8)
            }
            image = image.transformed(by: CGAffineTransform(translationX: rect.minX, y: output.height - rect.maxY - drop))
            layer = layer.map { image.composited(over: $0) } ?? image
        }
        return layer
    }

    static func keycapMargin(_ fontSize: CGFloat) -> CGFloat { ceil(fontSize * 0.9) }

    static func keycapRect(size: CGSize, position: KeystrokeSettings.Position, clearance: CGFloat, camera: CGRect?,
                           output: CGSize) -> CGRect {
        let atBottom = position == .bottom
        let margin = output.height * 0.06
        var rect = CGRect(x: ((output.width - size.width) / 2).rounded(), y: 0, width: size.width, height: size.height)
        rect.origin.y = (atBottom ? output.height - margin - size.height - clearance : margin + clearance).rounded()
        if let camera { rect = clear(rect, of: camera, atBottom: atBottom, margin: margin, output: output) }
        return rect
    }

    static func keycapImage(_ label: String, count: Int, fontSize f: CGFloat) -> CIImage? {
        let font = NSFont.systemFont(ofSize: f, weight: .semibold)
        let text = NSMutableAttributedString(string: label, attributes: [
            .font: font, .foregroundColor: CGColor(gray: 1, alpha: 1), .kern: f * 0.02,
        ])
        if count > 1 {
            text.append(NSAttributedString(string: "  ×\(count)", attributes: [
                .font: NSFont.systemFont(ofSize: f * 0.78, weight: .medium), .foregroundColor: CGColor(gray: 1, alpha: 0.55),
            ]))
        }
        let line = CTLineCreateWithAttributedString(text)
        let textWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let height = (f * 2).rounded()
        let pad = f * 0.66
        let width = max((textWidth + 2 * pad).rounded(.up), height)
        let m = keycapMargin(f)
        guard let ctx = CGContext(data: nil, width: Int(width + 2 * m), height: Int(height + 2 * m), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let plate = CGRect(x: m, y: m, width: width, height: height)
        let radius = height * 0.25
        let path = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -f * 0.12), blur: f * 0.6, color: CGColor(gray: 0, alpha: 0.32))
        ctx.addPath(path)
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        ctx.setBlendMode(.copy)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let colors = [CGColor(colorSpace: space, components: [0.03, 0.02, 0.045, 0.97])!,
                      CGColor(colorSpace: space, components: [0.11, 0.09, 0.14, 0.92])!] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: plate.maxY), end: CGPoint(x: 0, y: plate.minY), options: [])
        }
        ctx.restoreGState()
        let lw = max(f * 0.035, 1)
        let r = radius - lw / 2
        ctx.addPath(CGPath(roundedRect: plate.insetBy(dx: lw / 2, dy: lw / 2), cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.09))
        ctx.setLineWidth(lw)
        ctx.strokePath()
        ctx.textPosition = CGPoint(x: plate.minX + (width - textWidth) / 2, y: plate.minY + (height - font.capHeight) / 2)
        CTLineDraw(line, ctx)
        return ctx.makeImage().map { CIImage(cgImage: $0).transformed(by: CGAffineTransform(translationX: -m, y: -m)) }
    }
}
