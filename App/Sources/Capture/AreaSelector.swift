//
//  AreaSelector.swift
//  Slice
//
//  Created by rit3zh CX on 10/14/26.
//

import AppKit

@MainActor
final class AreaOverlay: ObservableObject {
    static let shared = AreaOverlay()

    enum Shape: CaseIterable, Identifiable {
        case free, widescreen, standard, square, vertical

        var id: Self { self }

        var ratio: CGFloat? {
            switch self {
            case .free: nil
            case .widescreen: 16.0 / 9
            case .standard: 4.0 / 3
            case .square: 1
            case .vertical: 9.0 / 16
            }
        }

        var title: String {
            switch self {
            case .free: "Any"
            case .widescreen: "16:9"
            case .standard: "4:3"
            case .square: "1:1"
            case .vertical: "9:16"
            }
        }

        var help: String {
            switch self {
            case .free: "Any shape you drag"
            case .widescreen: "Widescreen, like YouTube"
            case .standard: "Classic 4:3"
            case .square: "Square, like an Instagram post"
            case .vertical: "Tall, like TikTok, Reels and Shorts"
            }
        }
    }

    enum Mode { case hidden, editing, recording }

    @Published private(set) var displayID: CGDirectDisplayID?
    @Published private(set) var local: CGRect?
    @Published private(set) var shape: Shape = .free
    @Published private(set) var drawing = false

    private var mode: Mode = .hidden
    private var window: OverlayWindow?
    private var drawWindows: [OverlayWindow] = []
    private var drawn: CheckedContinuation<Bool, Never>?

    private var screen: NSScreen? { displayID.flatMap { id in NSScreen.screens.first { $0.displayID == id } } }

    var area: CaptureSource? {
        guard let id = displayID, let local, let screen else { return nil }
        let top = screen.topLeftFrame
        return .area(id, CGRect(x: top.minX + local.minX, y: top.minY + screen.frame.height - local.maxY,
                                width: local.width, height: local.height).integral)
    }

    func draw() async -> Bool {
        guard !drawing else { return false }
        drawing = true
        window?.orderOut(nil)
        return await withCheckedContinuation { cont in
            drawn = cont
            for screen in NSScreen.screens {
                let w = OverlayWindow(screen: screen)
                w.level = .screenSaver
                w.keyable = true
                w.area.ratio = shape.ratio
                w.area.phase = .drawing
                w.area.onPicked = { [weak self] rect in self?.finishDrawing(rect, on: screen) }
                w.makeKeyAndOrderFront(nil)
                drawWindows.append(w)
            }
            NSApp.activate(ignoringOtherApps: true)
            NSCursor.crosshair.set()
        }
    }

    private func finishDrawing(_ rect: CGRect?, on screen: NSScreen) {
        drawWindows.forEach { $0.orderOut(nil) }
        drawWindows = []
        drawing = false
        if let rect, let id = screen.displayID {
            displayID = id
            local = rect
            mode = .editing
            present(.editing, fade: false)
        } else {
            present(mode, fade: false)
        }
        NSCursor.arrow.set()
        drawn?.resume(returning: rect != nil)
        drawn = nil
    }

    func present(_ mode: Mode) { present(mode, fade: true) }

    private func present(_ mode: Mode, fade: Bool) {
        self.mode = mode
        guard !drawing else { return }
        guard mode != .hidden, let screen, var rect = local else {
            guard let window, window.isVisible else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                window.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated {
                    if self.mode == .hidden || self.local == nil { window.orderOut(nil) }
                }
            }
            return
        }
        let w = window ?? OverlayWindow(screen: screen)
        window = w
        w.setFrame(screen.frame, display: false)
        rect = rect.fitted(in: CGRect(origin: .zero, size: screen.frame.size))
        local = rect
        w.area.ratio = shape.ratio
        w.area.onChange = { [weak self] r in self?.local = r }
        w.area.set(rect)
        w.area.phase = mode == .recording ? .recording : .editing
        w.ignoresMouseEvents = mode == .recording
        if !w.isVisible || w.alphaValue < 1 {
            if !w.isVisible { w.alphaValue = fade ? 0 : 1 }
            w.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                w.animator().alphaValue = 1
            }
        }
    }

    func setShape(_ next: Shape) {
        shape = next
        window?.area.ratio = next.ratio
        guard let ratio = next.ratio, let local, let screen else { return }
        let bounds = CGRect(origin: .zero, size: screen.frame.size)
        let side = max((local.width * local.height * ratio).squareRoot(), AreaView.minSide * max(ratio, 1))
        var size = CGSize(width: side, height: side / ratio)
        let fit = min(1, bounds.width / size.width, bounds.height / size.height)
        size = CGSize(width: size.width * fit, height: size.height * fit)
        move(to: CGRect(x: local.midX - size.width / 2, y: local.midY - size.height / 2,
                        width: size.width, height: size.height).fitted(in: bounds))
    }

    func center() {
        guard let local, let screen else { return }
        let s = screen.frame.size
        move(to: CGRect(x: (s.width - local.width) / 2, y: (s.height - local.height) / 2,
                        width: local.width, height: local.height).fitted(in: CGRect(origin: .zero, size: s)))
    }

    func clear() {
        local = nil
        displayID = nil
        present(.hidden)
    }

    private func move(to rect: CGRect) {
        local = rect
        window?.area.set(rect, animated: true)
    }
}

private final class OverlayWindow: NSPanel {
    var keyable = false
    let area: AreaView

    override var canBecomeKey: Bool { keyable }

    init(screen: NSScreen) {
        area = AreaView(frame: CGRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        appearance = NSAppearance(named: .darkAqua)
        contentView = area
    }
}

final class BorderView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1.5, dy: 1.5), xRadius: 3, yRadius: 3)
        path.lineWidth = 1.5
        NSColor.white.withAlphaComponent(0.85).setStroke()
        path.stroke()
    }
}

extension CGRect {
    var rounded: CGRect {
        CGRect(x: minX.rounded(), y: minY.rounded(), width: width.rounded(), height: height.rounded())
    }

    func fitted(in bounds: CGRect) -> CGRect {
        let w = min(width, bounds.width), h = min(height, bounds.height)
        return CGRect(x: min(max(minX, bounds.minX), bounds.maxX - w), y: min(max(minY, bounds.minY), bounds.maxY - h),
                      width: w, height: h).rounded
    }
}
