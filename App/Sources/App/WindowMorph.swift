//
//  WindowMorph.swift
//  Slice
//
//  Created by rit3zh CX on 10/13/26.
//

import AppKit
import QuartzCore

/// Turns one window into another on screen: a surface grows out of a shape (the capture bar) into a window's frame and
/// hands over to it, or shrinks out of a window into the shape. The window itself never moves; an overlay above
/// everything draws the surface as a plain Core Animation layer, animated by the render server, so the move stays
/// smooth however busy the main thread is with the window's content (building it the first time especially).
@MainActor
enum WindowMorph {
    static let duration = 0.5
    static let handoff = 0.18

    static var windowRadius: CGFloat {
        if #available(macOS 26, *) { return 26 }
        return 10
    }

    private static var running: [NSWindow] = []

    static func reveal(_ window: NSWindow, from source: CGRect, radius: CGFloat) {
        let target = window.frame
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        let (overlay, surface) = makeOverlay(covering: source.union(target), rect: source, radius: radius)
        overlay.orderFrontRegardless()
        fade(surface, from: 0, to: 1, duration: 0.12, timing: .easeOut)
        move(surface, in: overlay, to: target, radius: windowRadius)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration * 0.84) {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = handoff
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                overlay.animator().alphaValue = 0
            } completionHandler: {
                finish(overlay)
            }
        }
    }

    static func collapse(_ window: NSWindow, into target: CGRect, radius: CGFloat) {
        let source = window.frame
        let (overlay, surface) = makeOverlay(covering: source.union(target), rect: source, radius: windowRadius)
        overlay.alphaValue = 0
        overlay.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = handoff * 0.7
            window.animator().alphaValue = 0
            overlay.animator().alphaValue = 1
        } completionHandler: {
            window.orderOut(nil)
            window.alphaValue = 1
        }
        move(surface, in: overlay, to: target, radius: radius)
        fade(surface, from: 1, to: 0, duration: 0.2, delay: 0.26, timing: .easeIn)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { finish(overlay) }
    }

    private static func move(_ surface: CALayer, in overlay: NSWindow, to rect: CGRect, radius: CGFloat) {
        let local = CGRect(x: rect.minX - overlay.frame.minX, y: rect.minY - overlay.frame.minY,
                           width: rect.width, height: rect.height)
        let to: [String: Any] = [
            "bounds": NSValue(rect: CGRect(origin: .zero, size: local.size)),
            "position": NSValue(point: CGPoint(x: local.midX, y: local.midY)),
            "cornerRadius": radius,
        ]
        for (key, value) in to {
            let spring = CASpringAnimation(perceptualDuration: duration, bounce: 0)
            spring.keyPath = key
            spring.fromValue = surface.value(forKeyPath: key)
            spring.toValue = value
            spring.duration = spring.settlingDuration
            spring.fillMode = .both
            surface.add(spring, forKey: key)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.bounds = CGRect(origin: .zero, size: local.size)
        surface.position = CGPoint(x: local.midX, y: local.midY)
        surface.cornerRadius = radius
        CATransaction.commit()
    }

    private static func fade(_ surface: CALayer, from: Float, to: Float, duration: Double, delay: Double = 0,
                             timing: CAMediaTimingFunctionName) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = duration
        fade.beginTime = delay > 0 ? CACurrentMediaTime() + delay : 0
        fade.timingFunction = CAMediaTimingFunction(name: timing)
        fade.fillMode = .both
        surface.add(fade, forKey: "opacity")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.opacity = to
        CATransaction.commit()
    }

    private static func makeOverlay(covering area: CGRect, rect: CGRect, radius: CGFloat) -> (NSWindow, CALayer) {
        let frame = area.insetBy(dx: -40, dy: -40)
        let overlay = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        overlay.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        let content = NSView(frame: CGRect(origin: .zero, size: frame.size))
        content.wantsLayer = true
        overlay.contentView = content

        let surface = CALayer()
        surface.backgroundColor = CGColor(srgbRed: 0.047, green: 0.047, blue: 0.055, alpha: 1)
        surface.borderColor = CGColor(gray: 1, alpha: 0.1)
        surface.borderWidth = 1
        surface.cornerCurve = .continuous
        surface.cornerRadius = radius
        surface.contentsScale = overlay.backingScaleFactor
        let local = CGRect(x: rect.minX - frame.minX, y: rect.minY - frame.minY, width: rect.width, height: rect.height)
        surface.bounds = CGRect(origin: .zero, size: local.size)
        surface.position = CGPoint(x: local.midX, y: local.midY)
        content.layer?.addSublayer(surface)
        running.append(overlay)
        return (overlay, surface)
    }

    private static func finish(_ overlay: NSWindow) {
        overlay.orderOut(nil)
        running.removeAll { $0 === overlay }
    }
}
