//
//  FrameRenderer+Captions.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/13/26.
//

import AppKit
import CoreImage
import CoreText

extension FrameRenderer {
    final class CaptionLayout {
        let text: CIImage
        let words: [[CGRect]]
        let plateSize: CGSize

        init(text: CIImage, words: [[CGRect]], plateSize: CGSize) {
            self.text = text
            self.words = words
            self.plateSize = plateSize
        }
    }

    struct CaptionMetrics {
        let fontSize: CGFloat
        var maxWidth: CGFloat
        let margin: CGFloat

        init(settings: SubtitleSettings, output: CGSize) {
            fontSize = (min(output.width, output.height) * settings.size).rounded()
            maxWidth = (output.width * 0.84).rounded()
            margin = output.height * 0.06
        }

        var gap: CGFloat { margin * 0.3 }
    }

    struct CaptionPlacement {
        var state: CaptionMotion.State
        var plate: CGRect
        var caption: Caption
        var layout: CaptionLayout
        var previous: (caption: Caption, layout: CaptionLayout)?
        var metrics: CaptionMetrics
    }

    static let captionGhost = 0.42

    func captionLayout(_ caption: Caption, metrics m: CaptionMetrics) -> CaptionLayout? {
        let key = "\(caption.start)|\(m.fontSize)|\(m.maxWidth)|\(caption.text)" as NSString
        if let cached = captionLayouts.object(forKey: key) { return cached }
        guard let made = Self.makeCaptionLayout(caption, fontSize: m.fontSize, maxWidth: m.maxWidth) else { return nil }
        captionLayouts.setObject(made, forKey: key)
        return made
    }

    func placedCaption(_ caption: Caption, settings: SubtitleSettings, metrics m: CaptionMetrics, camera: CGRect?,
                       output: CGSize) -> (layout: CaptionLayout, rect: CGRect)? {
        let atBottom = settings.position == .bottom
        func at(_ layout: CaptionLayout, centredIn lo: CGFloat, _ hi: CGFloat) -> CGRect {
            let size = layout.plateSize
            return CGRect(x: ((lo + hi - size.width) / 2).rounded(),
                          y: (atBottom ? output.height - m.margin - size.height : m.margin).rounded(),
                          width: size.width, height: size.height)
        }
        guard let layout = captionLayout(caption, metrics: m) else { return nil }
        let rect = at(layout, centredIn: 0, output.width)
        guard let camera, camera.intersects(rect) else { return (layout, rect) }
        let gap = m.margin * 0.5
        let beside = camera.midX > output.width / 2 ? (lo: gap, hi: camera.minX - gap) : (lo: camera.maxX + gap, hi: output.width - gap)
        if layout.plateSize.width <= beside.hi - beside.lo {
            var r = rect
            r.origin.x = min(max(r.minX, beside.lo), beside.hi - r.width).rounded()
            return (layout, r)
        }
        let room = ((beside.hi - beside.lo) / 32).rounded(.down) * 32
        if room >= max(output.width * 0.3, m.fontSize * 8) {
            var narrow = m
            narrow.maxWidth = room
            if let fitted = captionLayout(caption, metrics: narrow) {
                let r = at(fitted, centredIn: beside.lo, beside.hi)
                if !r.intersects(camera) { return (fitted, r) }
            }
        }
        return (layout, Self.clear(rect, of: camera, atBottom: atBottom, margin: m.margin, output: output))
    }

    func captionPlacement(at t: Double, captions: [Caption], settings: SubtitleSettings, camera: CGRect?,
                          output: CGSize) -> CaptionPlacement? {
        guard let s = CaptionMotion.state(at: t, in: captions) else { return nil }
        let m = CaptionMetrics(settings: settings, output: output)
        guard m.fontSize >= 4,
              let placed = placedCaption(captions[s.index], settings: settings, metrics: m, camera: camera, output: output)
        else { return nil }
        let layout = placed.layout
        var plate = placed.rect
        var previous: (Caption, CaptionLayout)?
        if let p = s.previous,
           let old = placedCaption(captions[p], settings: settings, metrics: m, camera: camera, output: output) {
            let before = old.layout, from = old.rect
            let k = CGFloat(s.shape)
            plate = CGRect(x: from.minX + (plate.minX - from.minX) * k, y: from.minY + (plate.minY - from.minY) * k,
                           width: from.width + (plate.width - from.width) * k, height: from.height + (plate.height - from.height) * k)
            previous = (captions[p], before)
        }
        return CaptionPlacement(state: s, plate: plate, caption: captions[s.index], layout: layout, previous: previous, metrics: m)
    }

    func drawCaption(_ c: CaptionPlacement, on image: CIImage, behind: CIImage, time t: Double, wordByWord: Bool,
                     output: CGSize) -> CIImage {
        let f = c.metrics.fontSize
        let s = c.state
        let plate = flip(c.plate, height: output.height)
        let radius = min(f * 0.42, plate.height / 2)
        let mask = roundedRect(plate, radius: radius)
        let sigma = Double(f) * 0.12
        let smoked = behind.clampedToExtent()
            .cropped(to: plate.insetBy(dx: -3 * sigma, dy: -3 * sigma))
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: plate)
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0.06, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0.06, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0.06, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: 0.004, y: 0.004, z: 0.004, w: 1),
            ])
        var layer = smoked.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
        ])

        let center = CGPoint(x: plate.midX, y: plate.midY)
        var words: CIImage = .empty()
        if let old = c.previous, s.outgoing < 1 {
            let o = s.outgoing
            words = captionWords(old.layout, caption: old.caption, center: center, time: t, wordByWord: wordByWord, fontSize: f,
                                 opacity: 1 - o * o * (3 - 2 * o), blur: 1 - pow(1 - o, 2), rise: 0.14 * o)
        }
        let a = s.incoming
        let settle = 1 - pow(1 - a, 3)
        words = captionWords(c.layout, caption: c.caption, center: center, time: t, wordByWord: wordByWord, fontSize: f,
                             opacity: 1 - pow(1 - min(a / 0.6, 1), 2), blur: 1 - settle, rise: -0.25 * (1 - settle))
            .composited(over: words)
        layer = words.applyingFilter("CIBlendWithAlphaMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: mask,
        ]).composited(over: layer)

        let bounds = layer.extent
        if s.blur > 0.002 {
            let sigma = s.blur * Double(f) * 0.35
            layer = layer.applyingGaussianBlur(sigma: sigma).cropped(to: bounds.insetBy(dx: -3 * sigma, dy: -3 * sigma))
        }
        if s.opacity < 0.998 { layer = scaleAlpha(layer, by: s.opacity) }
        if abs(s.scale - 1) > 0.0005 {
            layer = layer.transformed(by: CGAffineTransform(translationX: -center.x, y: -center.y)
                .concatenating(CGAffineTransform(scaleX: s.scale, y: s.scale))
                .concatenating(CGAffineTransform(translationX: center.x, y: center.y)))
        }
        if abs(s.drop) > 0.0005 { layer = layer.transformed(by: CGAffineTransform(translationX: 0, y: -s.drop * f)) }
        return layer.composited(over: image)
    }

    func captionWords(_ layout: CaptionLayout, caption: Caption, center: CGPoint, time t: Double, wordByWord: Bool,
                      fontSize f: CGFloat, opacity: Double, blur: Double, rise: Double) -> CIImage {
        guard opacity > 0.002 else { return .empty() }
        let e = layout.text.extent
        let x = (center.x - e.width / 2).rounded(), y = (center.y - e.height / 2).rounded() + rise * f
        let focus = caption.words.map { wordByWord ? CaptionMotion.focus(of: $0, at: t) : 1 }
        if blur < 0.002, focus.allSatisfy({ $0 >= 0.999 }) {
            let text = opacity < 0.998 ? scaleAlpha(layout.text, by: opacity) : layout.text
            return text.transformed(by: CGAffineTransform(translationX: x, y: y))
        }
        var out: CIImage?
        for (i, boxes) in layout.words.enumerated() where i < focus.count {
            let alpha = opacity * (Self.captionGhost + (1 - Self.captionGhost) * focus[i])
            guard alpha > 0.002 else { continue }
            for box in boxes {
                var piece = layout.text.cropped(to: box)
                if alpha < 0.998 { piece = scaleAlpha(piece, by: alpha) }
                out = out.map { piece.composited(over: $0) } ?? piece
            }
        }
        guard var words = out else { return .empty() }
        let sigma = blur * Double(f) * 0.3
        if sigma > 0.05 { words = words.applyingGaussianBlur(sigma: sigma).cropped(to: e.insetBy(dx: -3 * sigma, dy: -3 * sigma)) }
        return words.transformed(by: CGAffineTransform(translationX: x, y: y))
    }

    func captionClearance(at t: Double, captions: [Caption], settings: SubtitleSettings, camera: CGRect?,
                          output: CGSize) -> CGFloat {
        guard settings.burnIn, !captions.isEmpty else { return 0 }
        let m = CaptionMetrics(settings: settings, output: output)
        guard m.fontSize >= 4 else { return 0 }
        let lead = 0.25, settleDelay = CaptionMotion.outDuration, settle = 0.35
        func reach(_ i: Int) -> CGFloat {
            guard let r = placedCaption(captions[i], settings: settings, metrics: m, camera: camera, output: output)?.rect
            else { return 0 }
            return max(settings.position == .bottom ? output.height - m.margin - r.minY + m.gap : r.maxY + m.gap - m.margin, 0)
        }
        func smooth(_ x: Double) -> CGFloat {
            let x = min(max(x, 0), 1)
            return CGFloat(x * x * (3 - 2 * x))
        }
        var clearance: CGFloat = 0
        let last = CaptionMotion.lastStarted(at: t, in: captions)
        if let i = last {
            let c = captions[i]
            var r = reach(i)
            if i > 0, CaptionMotion.handsOver(i - 1, in: captions), t - c.start < CaptionMotion.swapDuration {
                let from = reach(i - 1)
                r = from + (r - from) * CGFloat(CaptionMotion.shapeEase(t - c.start))
            }
            if !CaptionMotion.handsOver(i, in: captions), t > c.end + settleDelay {
                r *= 1 - smooth((t - c.end - settleDelay) / settle)
            }
            clearance = r
        }
        let n = (last ?? -1) + 1
        if n < captions.count, !(n > 0 && CaptionMotion.handsOver(n - 1, in: captions)), captions[n].start - t < lead {
            clearance = max(clearance, reach(n) * smooth(1 - (captions[n].start - t) / lead))
        }
        return clearance
    }

    static func clear(_ rect: CGRect, of obstacle: CGRect, atBottom: Bool, margin: CGFloat, output: CGSize) -> CGRect {
        guard obstacle.intersects(rect) else { return rect }
        var rect = rect
        let gap = margin * 0.5
        let leftX = obstacle.minX - gap - rect.width, rightX = obstacle.maxX + gap
        if obstacle.midX > output.width / 2, leftX >= gap {
            rect.origin.x = leftX
        } else if obstacle.midX <= output.width / 2, rightX + rect.width <= output.width - gap {
            rect.origin.x = rightX
        } else {
            rect.origin.y = atBottom ? max(obstacle.minY - gap - rect.height, margin)
                : min(obstacle.maxY + gap, output.height - margin - rect.height)
        }
        return rect
    }

    static func makeCaptionLayout(_ caption: Caption, fontSize f: CGFloat, maxWidth: CGFloat) -> CaptionLayout? {
        guard !caption.words.isEmpty else { return nil }
        let base = NSFont.systemFont(ofSize: f, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: f) } ?? base
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byWordWrapping
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1), .paragraphStyle: para]
        let text = NSMutableAttributedString()
        var ranges: [(location: Int, end: Int)] = []
        for (i, w) in caption.words.enumerated() {
            if i > 0 { text.append(NSAttributedString(string: " ", attributes: attributes)) }
            let location = text.length
            text.append(NSAttributedString(string: w.text, attributes: attributes))
            ranges.append((location, text.length))
        }
        let pad = CGSize(width: (f * 0.56).rounded(), height: (f * 0.32).rounded())
        let setter = CTFramesetterCreateWithAttributedString(text)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil,
                                                              CGSize(width: max(maxWidth - 2 * pad.width, f), height: .greatestFiniteMagnitude), nil)
        let box = CGSize(width: ceil(fit.width), height: ceil(fit.height))
        let inset = ceil(f * 0.5)
        let size = CGSize(width: box.width + 2 * inset, height: box.height + 2 * inset)
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(origin: CGPoint(x: inset, y: inset), size: box),
                                                                         transform: nil), nil)
        CTFrameDraw(frame, ctx)
        guard let image = ctx.makeImage() else { return nil }

        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        let extents: [(top: CGFloat, bottom: CGFloat)] = lines.enumerated().map { k, line in
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let base = inset + origins[k].y
            return (base + ascent, base - descent)
        }
        var words = [[CGRect]](repeating: [], count: ranges.count)
        for (k, line) in lines.enumerated() {
            let lr = CTLineGetStringRange(line)
            let top = k == 0 ? size.height : (extents[k].top + extents[k - 1].bottom) / 2
            let bottom = k == lines.count - 1 ? 0 : (extents[k].bottom + extents[k + 1].top) / 2
            let x = inset + origins[k].x
            var pieces: [(word: Int, x0: CGFloat, x1: CGFloat)] = []
            for (j, r) in ranges.enumerated() {
                let lo = max(r.location, lr.location), hi = min(r.end, lr.location + lr.length)
                guard lo < hi else { continue }
                pieces.append((j, x + CTLineGetOffsetForStringIndex(line, lo, nil), x + CTLineGetOffsetForStringIndex(line, hi, nil)))
            }
            for (n, p) in pieces.enumerated() {
                let left = n == 0 ? 0 : (pieces[n - 1].x1 + p.x0) / 2
                let right = n == pieces.count - 1 ? size.width : (p.x1 + pieces[n + 1].x0) / 2
                words[p.word].append(CGRect(x: left, y: bottom, width: right - left, height: top - bottom))
            }
        }
        return CaptionLayout(text: CIImage(cgImage: image), words: words,
                             plateSize: CGSize(width: box.width + 2 * pad.width, height: box.height + 2 * pad.height))
    }
}
