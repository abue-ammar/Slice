//
//  AreaView+Mouse.swift
//  Slice
//
//  Created by rit3zh CX on 10/14/26.
//

import AppKit

extension AreaView {
    func handlePoints(_ r: CGRect) -> [(handle: Handle, point: CGPoint)] {
        var points: [(Handle, CGPoint)] = []
        for y in -1 ... 1 {
            for x in -1 ... 1 where x != 0 || y != 0 {
                if x == 0, r.width < 60 { continue }
                if y == 0, r.height < 60 { continue }
                points.append((.edge(x: x, y: y), CGPoint(x: r.midX + CGFloat(x) * r.width / 2, y: r.midY + CGFloat(y) * r.height / 2)))
            }
        }
        return points
    }

    func handle(at p: CGPoint) -> Handle {
        guard phase == .editing, let r = rect else { return .new }
        if let hit = handlePoints(r).min(by: { hypot($0.point.x - p.x, $0.point.y - p.y) < hypot($1.point.x - p.x, $1.point.y - p.y) }),
           hypot(hit.point.x - p.x, hit.point.y - p.y) <= Self.grab {
            return hit.handle
        }
        let g = Self.grab
        let nearX = abs(p.x - r.minX) <= g ? -1 : abs(p.x - r.maxX) <= g ? 1 : 0
        let nearY = abs(p.y - r.minY) <= g ? -1 : abs(p.y - r.maxY) <= g ? 1 : 0
        let alongX = p.x > r.minX - g && p.x < r.maxX + g, alongY = p.y > r.minY - g && p.y < r.maxY + g
        if nearX != 0, alongY { return .edge(x: nearX, y: 0) }
        if nearY != 0, alongX { return .edge(x: 0, y: nearY) }
        return r.contains(p) ? .move : .new
    }

    func cursor(for handle: Handle, dragging: Bool) -> NSCursor {
        switch handle {
        case .new: return .crosshair
        case .move: return dragging ? .closedHand : .openHand
        case let .edge(x, y):
            let position: NSCursor.FrameResizePosition = switch (x, y) {
            case (-1, 1): .topLeft
            case (1, 1): .topRight
            case (-1, -1): .bottomLeft
            case (1, -1): .bottomRight
            case (-1, _): .left
            case (1, _): .right
            case (_, 1): .top
            default: .bottom
            }
            return .frameResize(position: position, directions: .all)
        }
    }

    func location(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) {
        let p = location(event)
        let old = pointer
        pointer = p
        guard phase != .recording else { return }
        cursor(for: handle(at: p), dragging: false).set()
        guard phase == .drawing, rect == nil else { return }
        for q in [old, p].compactMap({ $0 }) {
            setNeedsDisplay(CGRect(x: 0, y: q.y - 2, width: bounds.width, height: 4))
            setNeedsDisplay(CGRect(x: q.x - 2, y: 0, width: 4, height: bounds.height))
        }
    }

    override func mouseExited(with event: NSEvent) {
        pointer = nil
        if phase == .drawing { needsDisplay = true }
    }

    override func mouseDown(with event: NSEvent) {
        guard phase != .recording else { return }
        stopGlide()
        let p = location(event)
        let h = handle(at: p)
        drag = Drag(handle: h, start: p, original: h == .new ? CGRect(origin: p, size: .zero) : rect ?? .zero, before: rect)
        cursor(for: h, dragging: true).set()
        if h == .new { rect = nil }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let drag else { return }
        rect = resized(drag, to: location(event))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let drag else { return }
        self.drag = nil
        let p = location(event)
        pointer = p
        let next = resized(drag, to: p)
        if drag.handle == .new, next.width < Self.minSide || next.height < Self.minSide {
            rect = drag.before
        } else {
            rect = next
            if phase == .drawing { onPicked?(next) } else { onChange?(next) }
        }
        if phase != .recording { cursor(for: handle(at: p), dragging: false).set() }
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53, phase == .drawing { onPicked?(nil) }
    }

    func resized(_ drag: Drag, to p: CGPoint) -> CGRect {
        let o = drag.original
        let dx = p.x - drag.start.x, dy = p.y - drag.start.y
        switch drag.handle {
        case .move:
            return o.offsetBy(dx: dx, dy: dy).fitted(in: bounds).rounded
        case .new:
            let x = dx < 0 ? -1 : 1, y = dy < 0 ? -1 : 1
            var size = CGSize(width: abs(dx), height: abs(dy))
            if let ratio {
                let w = max(size.width, size.height * ratio)
                size = CGSize(width: w, height: w / ratio)
            }
            return pinned(at: drag.start, x: x, y: y, size: size, minSide: 0)
        case let .edge(x, y):
            var size = CGSize(width: max(o.width + CGFloat(x) * dx, Self.minSide), height: max(o.height + CGFloat(y) * dy, Self.minSide))
            if let ratio {
                if x != 0, y != 0 {
                    let w = max(size.width, size.height * ratio)
                    size = CGSize(width: w, height: w / ratio)
                } else if x != 0 {
                    size.height = size.width / ratio
                } else {
                    size.width = size.height * ratio
                }
            }
            let fx: CGFloat = x == 1 ? 0 : x == -1 ? 1 : (ratio == nil ? 0 : 0.5)
            let fy: CGFloat = y == 1 ? 0 : y == -1 ? 1 : (ratio == nil ? 0 : 0.5)
            let anchor = CGPoint(x: o.minX + fx * o.width, y: o.minY + fy * o.height)
            return pinned(at: anchor, fx: fx, fy: fy, size: size, minSide: Self.minSide)
        }
    }

    func pinned(at anchor: CGPoint, x: Int, y: Int, size: CGSize, minSide: CGFloat) -> CGRect {
        pinned(at: anchor, fx: x == 1 ? 0 : 1, fy: y == 1 ? 0 : 1, size: size, minSide: minSide)
    }

    func pinned(at anchor: CGPoint, fx: CGFloat, fy: CGFloat, size: CGSize, minSide: CGFloat) -> CGRect {
        func room(_ a: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ f: CGFloat) -> CGFloat {
            f == 0 ? hi - a : f == 1 ? a - lo : 2 * min(a - lo, hi - a)
        }
        let maxW = room(anchor.x, bounds.minX, bounds.maxX, fx), maxH = room(anchor.y, bounds.minY, bounds.maxY, fy)
        var w = size.width, h = size.height
        if ratio != nil {
            let scale = min(1, maxW / max(w, 1), maxH / max(h, 1))
            w *= scale
            h *= scale
        } else {
            w = min(w, maxW)
            h = min(h, maxH)
        }
        w = max(w, min(minSide, maxW))
        h = max(h, min(minSide, maxH))
        return CGRect(x: anchor.x - fx * w, y: anchor.y - fy * h, width: w, height: h).rounded
    }
}
