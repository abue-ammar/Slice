//
//  AnnotationPainter.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/20/26.
//

import AppKit
import CoreGraphics
import CoreText

/// Draws annotations the same way on the live overlay and in the video. The context's y axis points up; `place` turns
/// a stored point into the context's space and `scale` turns a screen point into its units.
public enum AnnotationPainter {
    public static let highlighterAlpha = 0.38

    public static func draw(_ annotations: [Annotation], at t: Double, in ctx: CGContext, scale: CGFloat,
                            place: (CGPoint) -> CGPoint) {
        for a in annotations {
            let n = a.drawnCount(at: t)
            guard n > 0 else { continue }
            draw(a, count: n, in: ctx, scale: scale, place: place)
        }
    }

    public static func draw(_ a: Annotation, count n: Int, in ctx: CGContext, scale: CGFloat, place: (CGPoint) -> CGPoint) {
        let pts = a.points.prefix(n).map { place($0.location) }
        guard let first = pts.first, let last = pts.last else { return }
        let w = strokeWidth(a) * scale
        let alpha = a.tool == .highlighter ? highlighterAlpha : 1
        let color = CGColor(srgbRed: a.color.r, green: a.color.g, blue: a.color.b, alpha: a.color.a * alpha)
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch a.tool {
        case .pen, .highlighter:
            if pts.count == 1 {
                ctx.fillEllipse(in: CGRect(x: first.x - w / 2, y: first.y - w / 2, width: w, height: w))
            } else {
                ctx.addPath(smoothPath(pts))
                ctx.strokePath()
            }
        case .line:
            guard first != last else { return }
            ctx.move(to: first)
            ctx.addLine(to: last)
            ctx.strokePath()
        case .arrow:
            drawArrow(from: first, to: last, width: w, in: ctx)
        case .rectangle:
            let r = CGRect(from: first, to: last)
            guard r.width > 0 || r.height > 0 else { return }
            let radius = min(w * 1.2, min(r.width, r.height) / 2)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.strokePath()
        case .ellipse:
            let r = CGRect(from: first, to: last)
            guard r.width > 0 || r.height > 0 else { return }
            ctx.strokeEllipse(in: r)
        case .text:
            guard let text = a.text, !text.isEmpty else { return }
            let font = labelFont(a, scale: scale)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            ctx.textMatrix = .identity
            for (i, line) in text.components(separatedBy: "\n").enumerated() {
                let ct = CTLineCreateWithAttributedString(NSAttributedString(string: line, attributes: attributes))
                ctx.textPosition = CGPoint(x: first.x, y: first.y - font.ascender - CGFloat(i) * lineHeight(font))
                CTLineDraw(ct, ctx)
            }
        }
    }

    /// What `draw` covers, in the context's space.
    public static func bounds(of a: Annotation, count n: Int, scale: CGFloat, place: (CGPoint) -> CGPoint) -> CGRect {
        let pts = a.points.prefix(n).map { place($0.location) }
        guard let first = pts.first else { return .null }
        if a.tool == .text {
            let font = labelFont(a, scale: scale)
            let lines = (a.text ?? "").components(separatedBy: "\n")
            let width = lines.map { line in
                CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(
                    NSAttributedString(string: line, attributes: [.font: font])), nil, nil, nil))
            }.max() ?? 0
            let height = CGFloat(lines.count) * lineHeight(font)
            return CGRect(x: first.x, y: first.y - height, width: width, height: height).insetBy(dx: -4 * scale, dy: -4 * scale)
        }
        let box = a.tool == .pen || a.tool == .highlighter ? pts.dropFirst().reduce(CGRect(origin: first, size: .zero)) {
            $0.union(CGRect(origin: $1, size: .zero))
        } : CGRect(from: first, to: pts.last ?? first)
        let w = strokeWidth(a) * scale
        let pad = a.tool == .arrow ? arrowHead(width: w) : w
        return box.insetBy(dx: -pad - 2, dy: -pad - 2)
    }

    public static func strokeWidth(_ a: Annotation) -> CGFloat {
        a.tool == .highlighter ? CGFloat(a.width) * 3 + 6 : CGFloat(a.width)
    }

    public static func labelFont(_ a: Annotation, scale: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: CGFloat(a.fontSize) * scale, weight: .semibold)
    }

    public static func lineHeight(_ font: NSFont) -> CGFloat { (font.ascender - font.descender + font.leading).rounded(.up) }

    /// Through the midpoints of the points, curving at each one, so a quick stroke reads smooth rather than faceted.
    static func smoothPath(_ pts: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        path.move(to: pts[0])
        guard pts.count > 2 else {
            path.addLine(to: pts[pts.count - 1])
            return path
        }
        for i in 1 ..< pts.count - 1 {
            let mid = CGPoint(x: (pts[i].x + pts[i + 1].x) / 2, y: (pts[i].y + pts[i + 1].y) / 2)
            path.addQuadCurve(to: mid, control: pts[i])
        }
        path.addLine(to: pts[pts.count - 1])
        return path
    }

    static func arrowHead(width w: CGFloat) -> CGFloat { w * 3 + 8 * max(w / 4, 1) }

    static func drawArrow(from a: CGPoint, to b: CGPoint, width w: CGFloat, in ctx: CGContext) {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0.5 else { return }
        let ux = dx / length, uy = dy / length
        let head = min(arrowHead(width: w), length)
        let half = head * 0.55
        let base = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
        if length > head {
            ctx.move(to: a)
            ctx.addLine(to: CGPoint(x: base.x + ux * w * 0.5, y: base.y + uy * w * 0.5))
            ctx.strokePath()
        }
        ctx.move(to: b)
        ctx.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
        ctx.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
        ctx.closePath()
        ctx.setLineWidth(w * 0.6)
        ctx.drawPath(using: .fillStroke)
    }
}

extension CGRect {
    init(from a: CGPoint, to b: CGPoint) {
        self.init(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }
}
