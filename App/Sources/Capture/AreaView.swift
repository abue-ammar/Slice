//
//  AreaView.swift
//  Slice
//
//  Created by rit3zh CX on 10/14/26.
//

import AppKit

final class AreaView: NSView {
    enum Phase { case drawing, editing, recording }

    static let minSide: CGFloat = 64
    static let handleRadius: CGFloat = 5
    static let grab: CGFloat = 10
    static let dim = NSColor.black.withAlphaComponent(0.45)

    var phase: Phase = .drawing {
        didSet {
            guard phase != oldValue else { return }
            updateBlur()
            needsDisplay = true
        }
    }
    var ratio: CGFloat?
    var onPicked: ((CGRect?) -> Void)?
    var onChange: ((CGRect) -> Void)?

    var rect: CGRect?
    var pointer: CGPoint?
    var drag: Drag?
    var glide: (from: CGRect, to: CGRect, start: CFTimeInterval)?
    var glideTimer: Timer?
    var blur: [NSView] = []
    let border = BorderView()

    enum Handle: Equatable {
        case new
        case move
        case edge(x: Int, y: Int)
    }

    struct Drag {
        let handle: Handle
        let start: CGPoint
        let original: CGRect
        let before: CGRect?
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    func set(_ next: CGRect, animated: Bool = false) {
        guard animated, let from = rect, from != next else {
            stopGlide()
            rect = next
            layoutBlur()
            needsDisplay = true
            return
        }
        glide = (from, next, CACurrentMediaTime())
        if glideTimer == nil {
            let t = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.stepGlide() }
            }
            RunLoop.main.add(t, forMode: .common)
            glideTimer = t
        }
    }

    func stepGlide() {
        guard let glide else { return stopGlide() }
        let t = min((CACurrentMediaTime() - glide.start) / 0.28, 1)
        let e = 1 - pow(1 - t, 3)
        let a = glide.from, b = glide.to
        rect = CGRect(x: a.minX + (b.minX - a.minX) * e, y: a.minY + (b.minY - a.minY) * e,
                      width: a.width + (b.width - a.width) * e, height: a.height + (b.height - a.height) * e)
        if t >= 1 {
            rect = b
            stopGlide()
        }
        layoutBlur()
        needsDisplay = true
    }

    func stopGlide() {
        glideTimer?.invalidate()
        glideTimer = nil
        glide = nil
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        Self.dim.setFill()
        bounds.fill()
        guard let r = rect else {
            if phase == .drawing { drawCrosshair(); drawHint() }
            return
        }
        NSColor.clear.setFill()
        r.fill(using: .copy)
        guard phase != .recording else { return }
        if drag != nil, drag?.handle != .new || r.width > 90 { drawThirds(r) }
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: r.insetBy(dx: -0.5, dy: -0.5))
        outline.lineWidth = 1
        outline.stroke()
        if phase == .editing { drawHandles(r) }
        drawSize(r)
    }

    func drawCrosshair() {
        guard let p = pointer, drag == nil else { return }
        NSColor.white.withAlphaComponent(0.28).setFill()
        CGRect(x: 0, y: p.y.rounded() - 0.5, width: bounds.width, height: 1).fill()
        CGRect(x: p.x.rounded() - 0.5, y: 0, width: 1, height: bounds.height).fill()
    }

    func drawHint() {
        guard drag == nil else { return }
        let title = "Drag to select the area to record" as NSString
        let detail = "You can move and resize it afterwards. Press esc to cancel." as NSString
        let titleAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white,
                                                         .font: NSFont.systemFont(ofSize: 17, weight: .semibold)]
        let detailAttrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white.withAlphaComponent(0.7),
                                                          .font: NSFont.systemFont(ofSize: 12.5, weight: .regular)]
        let t = title.size(withAttributes: titleAttrs), d = detail.size(withAttributes: detailAttrs)
        let size = CGSize(width: max(t.width, d.width) + 48, height: t.height + d.height + 6 + 32)
        let card = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
        let shape = NSBezierPath(roundedRect: card, xRadius: 16, yRadius: 16)
        NSColor.black.withAlphaComponent(0.6).setFill()
        shape.fill()
        NSColor.white.withAlphaComponent(0.12).setStroke()
        shape.lineWidth = 1
        shape.stroke()
        title.draw(at: CGPoint(x: card.midX - t.width / 2, y: card.maxY - 16 - t.height), withAttributes: titleAttrs)
        detail.draw(at: CGPoint(x: card.midX - d.width / 2, y: card.minY + 16), withAttributes: detailAttrs)
    }

    func drawThirds(_ r: CGRect) {
        NSColor.white.withAlphaComponent(0.22).setFill()
        for i in 1 ... 2 {
            let f = CGFloat(i) / 3
            CGRect(x: (r.minX + r.width * f).rounded() - 0.5, y: r.minY, width: 1, height: r.height).fill()
            CGRect(x: r.minX, y: (r.minY + r.height * f).rounded() - 0.5, width: r.width, height: 1).fill()
        }
    }

    func drawHandles(_ r: CGRect) {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = CGSize(width: 0, height: -1)
        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        NSColor.white.setFill()
        for p in handlePoints(r).map(\.point) {
            let d = Self.handleRadius * 2
            NSBezierPath(ovalIn: CGRect(x: p.x - d / 2, y: p.y - d / 2, width: d, height: d)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    func drawSize(_ r: CGRect) {
        var text = "\(Int(r.width)) × \(Int(r.height))"
        if let ratio, let shape = AreaOverlay.Shape.allCases.first(where: { $0.ratio == ratio }) { text += "  ·  \(shape.title)" }
        let base = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 12) } ?? base
        let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: font]
        let s = (text as NSString).size(withAttributes: attrs)
        let pill = CGSize(width: s.width + 20, height: 24)
        var origin = CGPoint(x: r.midX - pill.width / 2, y: r.minY - pill.height - 12)
        if origin.y < 8 { origin.y = r.minY + 12 }
        origin.x = min(max(origin.x, 8), bounds.maxX - pill.width - 8)
        let frame = CGRect(origin: origin, size: pill)
        NSColor.black.withAlphaComponent(0.72).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12).fill()
        (text as NSString).draw(at: CGPoint(x: frame.minX + 10, y: frame.midY - s.height / 2), withAttributes: attrs)
    }

    // MARK: Recording

    func updateBlur() {
        guard phase == .recording else {
            let leaving = blur + [border]
            blur = []
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                leaving.forEach { $0.animator().alphaValue = 0 }
            } completionHandler: {
                MainActor.assumeIsolated { leaving.forEach { $0.removeFromSuperview() } }
            }
            return
        }
        blur = (0 ..< 4).map { _ in
            let v = NSVisualEffectView()
            v.material = .hudWindow
            v.blendingMode = .behindWindow
            v.state = .active
            let shade = NSView()
            shade.wantsLayer = true
            shade.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
            shade.autoresizingMask = [.width, .height]
            v.addSubview(shade)
            v.alphaValue = 0
            addSubview(v)
            return v
        }
        border.alphaValue = 0
        addSubview(border)
        layoutBlur()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.35
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            (blur + [border]).forEach { $0.animator().alphaValue = 1 }
        }
    }

    func layoutBlur() {
        guard !blur.isEmpty, let r = rect else { return }
        let b = bounds
        let frames = [
            CGRect(x: 0, y: 0, width: b.width, height: r.minY),
            CGRect(x: 0, y: r.maxY, width: b.width, height: b.height - r.maxY),
            CGRect(x: 0, y: r.minY, width: r.minX, height: r.height),
            CGRect(x: r.maxX, y: r.minY, width: b.width - r.maxX, height: r.height),
        ]
        for (v, f) in zip(blur, frames) {
            v.frame = f
            v.subviews.first?.frame = v.bounds
        }
        border.frame = r.insetBy(dx: -3, dy: -3)
    }
}
