//
//  PhonePreviewView.swift
//  Slice
//
//  Created by rit3zh CX on 10/5/26.
//

import AppKit
import Metal
import QuartzCore
import SliceCore
import SwiftUI

final class PhonePreviewSource: @unchecked Sendable {
    private let lock = NSLock()
    private var stream: DeviceStream?
    private var frame: DeviceFrameTextures?
    private var model: DeviceModel?
    private var morph: (from: DeviceFrameTextures, start: CFTimeInterval)?
    private var version = 0

    func update(stream: DeviceStream?) {
        lock.withLock {
            self.stream = stream
            version &+= 1
        }
    }

    func update(frame: DeviceFrameTextures, model: DeviceModel?) {
        lock.withLock {
            if let current = self.frame, current.definition != frame.definition {
                morph = (current, CACurrentMediaTime())
            }
            self.frame = frame
            self.model = model
            version &+= 1
        }
    }

    struct Snapshot {
        var stream: DeviceStream?
        var frame: DeviceFrameTextures?
        var model: DeviceModel?
        var morph: (from: DeviceFrameTextures, start: CFTimeInterval)?
        var version: Int
        var latest: DeviceStream.Frame?

        func morphProgress(at now: CFTimeInterval) -> CGFloat? {
            guard let morph else { return nil }
            let t = (now - morph.start) / DeviceMorph.duration
            return t < 1 ? CGFloat(DeviceMorph.eased(t)) : nil
        }

        var layout: DeviceLayout? {
            frame.map { DeviceLayout(frame: $0.definition, streamSize: latest.map(Self.size)) }
        }

        static func size(_ f: DeviceStream.Frame) -> CGSize {
            CGSize(width: CVPixelBufferGetWidth(f.buffer), height: CVPixelBufferGetHeight(f.buffer))
        }
    }

    func snapshot() -> Snapshot {
        let (stream, frame, model, morph, version) = lock.withLock {
            (self.stream, self.frame, self.model, self.morph, self.version)
        }
        return Snapshot(stream: stream, frame: frame, model: model, morph: morph, version: version, latest: stream?.latest)
    }
}

struct PhonePreview: NSViewRepresentable {
    let source: PhonePreviewSource
    var movesWindow = false
    var menu: (() -> NSMenu?)?

    func makeNSView(context: Context) -> PhonePreviewNSView { PhonePreviewNSView(source: source) }

    func updateNSView(_ view: PhonePreviewNSView, context: Context) {
        view.movesWindow = movesWindow
        view.menuProvider = menu
        view.window?.invalidateCursorRects(for: view)
    }
}

final class PhonePreviewNSView: NSView, CAMetalDisplayLinkDelegate {
    var movesWindow = false
    var menuProvider: (() -> NSMenu?)?
    private var resizing: (corner: Corner, frame: CGRect, mouse: CGPoint)?

    enum Corner { case topLeft, topRight, bottomLeft, bottomRight }
    private let source: PhonePreviewSource
    private let metalLayer = CAMetalLayer()
    private var link: CAMetalDisplayLink?
    private var occlusionObserver: NSObjectProtocol?

    private var mipmapped: MipmappedScreen?
    private var morph: DeviceMorph?
    private var lastDrawn: DrawKey?

    private struct DrawKey: Equatable {
        var frame: Int
        var version: Int
        var size: CGSize
        var morph: CGFloat?
    }

    init(source: PhonePreviewSource) {
        self.source = source
        super.init(frame: .zero)
        let compositor = DeviceCompositor.shared
        metalLayer.device = compositor?.device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        metalLayer.isOpaque = false
        metalLayer.maximumDrawableCount = 3
        metalLayer.contentsGravity = .resizeAspect
        layer = metalLayer
        wantsLayer = true
        mipmapped = compositor.map(MipmappedScreen.init)
        morph = compositor.flatMap(DeviceMorph.init)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit {
        link?.invalidate()
        occlusionObserver.map(NotificationCenter.default.removeObserver)
    }

    override var isFlipped: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Invalidating the link removes the render thread's only run loop source, which ends the thread.
        link?.invalidate()
        link = nil
        occlusionObserver.map(NotificationCenter.default.removeObserver)
        occlusionObserver = nil
        guard let window else { return }
        updateDrawableSize()
        let l = CAMetalDisplayLink(metalLayer: metalLayer)
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
        l.preferredFrameLatency = 1
        l.delegate = self
        link = l
        let thread = Thread {
            l.add(to: .current, forMode: .default)
            while !Thread.current.isCancelled, RunLoop.current.run(mode: .default, before: .distantFuture) {}
        }
        thread.name = "Device preview render"
        thread.qualityOfService = .userInteractive
        thread.start()
        occlusionObserver = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification,
                                                                   object: window, queue: .main) { [weak self, weak window] _ in
            self?.link?.isPaused = !(window?.occlusionState.contains(.visible) ?? false)
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateDrawableSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateDrawableSize()
    }

    private func updateDrawableSize() {
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        let size = CGSize(width: max((bounds.width * scale).rounded(), 2), height: max((bounds.height * scale).rounded(), 2))
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
    }

    // MARK: - Render thread

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        guard let compositor = DeviceCompositor.shared else { return }
        let snap = source.snapshot()
        let drawable = update.drawable
        let size = CGSize(width: drawable.texture.width, height: drawable.texture.height)
        let progress = snap.morphProgress(at: update.targetPresentationTimestamp)
        let key = DrawKey(frame: snap.latest?.sequence ?? 0, version: snap.version, size: size, morph: progress)
        guard key != lastDrawn, let frame = snap.frame, let layout = snap.layout,
              let commands = compositor.commandQueue.makeCommandBuffer() else { return }
        if lastDrawn?.morph != nil, progress == nil { morph?.purge() }
        lastDrawn = key
        let screen = snap.latest.flatMap { mipmapped?.texture(for: $0.buffer, commands: commands) }
        if let progress, let from = snap.morph?.from, let morph {
            let previous = DeviceLayout(frame: from.definition, streamSize: layout.streamSize)
            morph.encode(into: commands, target: drawable.texture, from: DeviceLook(frame: from, layout: previous),
                         to: DeviceLook(frame: frame, layout: layout), screen: screen, progress: progress)
        } else {
            compositor.encode(into: commands, target: drawable.texture, rect: layout.fitted(in: size), frame: frame,
                              layout: layout, screen: screen)
        }
        commands.present(drawable)
        commands.commit()
    }

    // MARK: - Moving and resizing

    private func point(_ event: NSEvent) -> CGPoint { convert(event.locationInWindow, from: nil) }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        guard movesWindow, let window else { return }
        if let corner = corner(at: p) {
            resizing = (corner, window.frame, NSEvent.mouseLocation)
        } else {
            window.performDrag(with: event)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if let resizing { resize(resizing) }
    }

    override func mouseUp(with event: NSEvent) {
        guard resizing != nil else { return }
        resizing = nil
        window?.invalidateShadow()
        window?.invalidateCursorRects(for: self)
    }

    override func magnify(with event: NSEvent) {
        guard movesWindow, let window else { return }
        let f = window.frame
        let k = max(1 + event.magnification, 0.5)
        DeviceWindowController.setFrame(of: window, size: CGSize(width: f.width * k, height: f.height * k), around: CGPoint(x: f.midX, y: f.midY))
        if event.phase == .ended { window.invalidateShadow() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }

    private func corner(at p: CGPoint) -> Corner? {
        guard let layout = source.snapshot().layout else { return nil }
        let c = layout.fitted(in: bounds.size)
        let reach = min(c.width, c.height) * 0.22
        let left = p.x < c.minX + reach, right = p.x > c.maxX - reach
        let top = p.y < c.minY + reach, bottom = p.y > c.maxY - reach
        switch (left, right, top, bottom) {
        case (true, _, true, _): return .topLeft
        case (_, true, true, _): return .topRight
        case (true, _, _, true): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: return nil
        }
    }

    private func resize(_ r: (corner: Corner, frame: CGRect, mouse: CGPoint)) {
        guard let window else { return }
        let m = NSEvent.mouseLocation
        let dx = m.x - r.mouse.x
        let grow: CGFloat = switch r.corner {
        case .topRight, .bottomRight: dx
        case .topLeft, .bottomLeft: -dx
        }
        let width = r.frame.width + grow
        let size = CGSize(width: width, height: width * r.frame.height / r.frame.width)
        let anchor: CGPoint = switch r.corner {
        case .topLeft: CGPoint(x: r.frame.maxX, y: r.frame.minY)
        case .topRight: CGPoint(x: r.frame.minX, y: r.frame.minY)
        case .bottomLeft: CGPoint(x: r.frame.maxX, y: r.frame.maxY)
        case .bottomRight: CGPoint(x: r.frame.minX, y: r.frame.maxY)
        }
        DeviceWindowController.setFrame(of: window, size: size, anchor: anchor, corner: r.corner)
    }

    override func resetCursorRects() {
        guard let layout = source.snapshot().layout else { return }
        let c = layout.fitted(in: bounds.size)
        if movesWindow {
            let reach = min(c.width, c.height) * 0.22
            let corners: [(CGRect, NSCursor.FrameResizePosition)] = [
                (CGRect(x: c.minX, y: c.minY, width: reach, height: reach), .topLeft),
                (CGRect(x: c.maxX - reach, y: c.minY, width: reach, height: reach), .topRight),
                (CGRect(x: c.minX, y: c.maxY - reach, width: reach, height: reach), .bottomLeft),
                (CGRect(x: c.maxX - reach, y: c.maxY - reach, width: reach, height: reach), .bottomRight),
            ]
            addCursorRect(c, cursor: .openHand)
            for (rect, position) in corners { addCursorRect(rect, cursor: .frameResize(position: position, directions: .all)) }
        }
    }
}
