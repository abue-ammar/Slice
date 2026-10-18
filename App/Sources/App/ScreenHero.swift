//
//  ScreenHero.swift
//  Slice
//
//  Created by rit3zh CX on 10/18/26.
//

import AppKit
import QuartzCore

/// A picture that flies between two screens of the main window (a project card and the editor's preview), over a
/// backdrop that hides the swap underneath. Everything is a Core Animation layer in a child window, animated by the
/// render server, so building the next screen on the main thread can't stutter it. Moves are additive springs: a new
/// target mid-flight bends the path without a jump or a lost velocity.
@MainActor
final class ScreenHero {
    static let duration = 0.52
    static let bounce = 0.14
    /// Close enough to rest that a handoff to identical pixels can't be seen.
    static let settled = 0.62
    static let cardRadius: CGFloat = 12

    private let overlay: MorphPanel
    private let backdrop = CALayer()
    /// The picture and its shadow, faded as one: faded apart, the shadow's fill shows through mid-fade as a dark flicker.
    private let group = CALayer()
    private let shadow = CALayer()
    private let picture = CALayer()
    private weak var parent: NSWindow?
    private(set) var target: CGRect
    private let started = CACurrentMediaTime()

    /// Seconds since the hero appeared.
    var age: Double { CACurrentMediaTime() - started }

    /// `rect` is in the window's coordinates (bottom-left origin), as `NSView.convert(_:to: nil)` gives them.
    /// `zoomed` is how far the card had scaled its picture up under the pointer; the flight eases it back out.
    init(over window: NSWindow, image: CGImage?, at rect: CGRect, fills: Bool, shadowed: Bool, zoomed: CGFloat = 1) {
        parent = window
        target = rect
        overlay = MorphPanel(contentRect: window.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.isReleasedWhenClosed = false
        overlay.collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        let content = NSView(frame: CGRect(origin: .zero, size: window.frame.size))
        content.wantsLayer = true
        overlay.contentView = content
        let root = content.layer!
        root.masksToBounds = true
        root.cornerCurve = .continuous
        root.cornerRadius = window.styleMask.contains(.fullScreen) ? 0 : WindowMorph.windowRadius

        without {
            backdrop.frame = root.bounds
            backdrop.backgroundColor = CGColor(srgbRed: 0.047, green: 0.047, blue: 0.055, alpha: 1)
            backdrop.opacity = 0
            root.addSublayer(backdrop)
            group.frame = root.bounds
            group.allowsGroupOpacity = true
            root.addSublayer(group)

            shadow.backgroundColor = CGColor(srgbRed: 0.078, green: 0.078, blue: 0.09, alpha: 1)
            shadow.shadowColor = .black
            shadow.shadowOpacity = shadowed ? 0.45 : 0
            shadow.shadowRadius = 22
            shadow.shadowOffset = CGSize(width: 0, height: -14)
            group.addSublayer(shadow)

            picture.contents = image
            picture.contentsGravity = fills ? .resizeAspectFill : .resizeAspect
            picture.backgroundColor = shadow.backgroundColor
            picture.masksToBounds = true
            picture.borderWidth = 1
            picture.borderColor = CGColor(gray: 1, alpha: 0.06)
            picture.contentsScale = window.backingScaleFactor
            picture.minificationFilter = .trilinear
            group.addSublayer(picture)

            for layer in [shadow, picture] {
                layer.cornerCurve = .continuous
                layer.cornerRadius = Self.cardRadius
                layer.bounds = CGRect(origin: .zero, size: rect.size)
                layer.position = CGPoint(x: rect.midX, y: rect.midY)
            }
        }
        if fills, zoomed > 1 {
            let inset = (1 - 1 / zoomed) / 2
            let a = CASpringAnimation(perceptualDuration: Self.duration, bounce: 0)
            a.keyPath = "contentsRect"
            a.fromValue = NSValue(rect: CGRect(x: inset, y: inset, width: 1 - 2 * inset, height: 1 - 2 * inset))
            a.toValue = NSValue(rect: CGRect(x: 0, y: 0, width: 1, height: 1))
            a.duration = a.settlingDuration
            picture.add(a, forKey: "contentsRect")
        }
        overlay.setFrame(window.frame, display: false)
        window.addChildWindow(overlay, ordered: .above)
        CATransaction.flush()
    }

    // MARK: Motion

    /// Springs the picture to `rect` from wherever it is now, keeping its speed.
    func move(to rect: CGRect) {
        let from = target
        target = rect
        let dPosition = CGPoint(x: from.midX - rect.midX, y: from.midY - rect.midY)
        let dSize = CGSize(width: from.width - rect.width, height: from.height - rect.height)
        for layer in [shadow, picture] {
            without {
                layer.bounds = CGRect(origin: .zero, size: rect.size)
                layer.position = CGPoint(x: rect.midX, y: rect.midY)
            }
            layer.add(spring("position", from: NSValue(point: dPosition), to: NSValue(point: .zero)), forKey: nil)
            layer.add(spring("bounds.size", from: NSValue(size: dSize), to: NSValue(size: .zero)), forKey: nil)
        }
    }

    func shadow(to opacity: Float, duration: Double, delay: Double = 0) {
        fade(shadow, key: "shadowOpacity", to: opacity, duration: duration, delay: delay, timing: .easeInEaseOut)
    }

    func backdrop(to opacity: Float, duration: Double, delay: Double = 0) {
        fade(backdrop, key: "opacity", to: opacity, duration: duration, delay: delay, timing: opacity > 0 ? .easeOut : .easeInEaseOut)
    }

    /// Dissolves the picture into whatever is underneath and takes the overlay away.
    func finish(fade duration: Double = 0.16, delay: Double = 0) {
        fade(group, key: "opacity", to: 0, duration: duration, delay: delay, timing: .easeOut)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.02) { [self] in remove() }
    }

    func remove() {
        parent?.removeChildWindow(overlay)
        overlay.orderOut(nil)
    }

    // MARK: Helpers

    private func spring(_ key: String, from: Any, to: Any) -> CASpringAnimation {
        let a = CASpringAnimation(perceptualDuration: Self.duration, bounce: Self.bounce)
        a.keyPath = key
        a.isAdditive = true
        a.fromValue = from
        a.toValue = to
        a.duration = a.settlingDuration
        a.fillMode = .backwards
        return a
    }

    private func fade(_ layer: CALayer, key: String, to value: Float, duration: Double, delay: Double,
                      timing: CAMediaTimingFunctionName) {
        let a = CABasicAnimation(keyPath: key)
        a.fromValue = (layer.presentation() ?? layer).value(forKey: key)
        a.toValue = value
        a.duration = duration
        a.beginTime = delay > 0 ? layer.convertTime(CACurrentMediaTime(), from: nil) + delay : 0
        a.timingFunction = CAMediaTimingFunction(name: timing)
        a.fillMode = .backwards
        layer.add(a, forKey: key)
        without { layer.setValue(value, forKey: key) }
    }

    private func without(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }
}
