//
//  AnnotationCanvas.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import AppKit
import SliceCore

/// A clear panel over one display that shows the marks and, while drawing, takes the mouse. It's Slice's own window,
/// and the capture filter leaves Slice's windows out, so it never records itself: the video draws the marks from the
/// take's log instead.
final class AnnotationCanvasPanel: NSPanel {
    let canvas: AnnotationCanvasView
    var keyable = false

    override var canBecomeKey: Bool { keyable }

    /// Above the Dock and menu bar, as the marks are in the video; the bar is raised above this while recording.
    static let level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue)

    init(screen: NSScreen, session: AnnotationSession) {
        canvas = AnnotationCanvasView(session: session)
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = Self.level
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        appearance = NSAppearance(named: .darkAqua)
        contentView = canvas
    }

    func place(on screen: NSScreen) {
        setFrame(screen.frame, display: false)
        canvas.needsDisplay = true
    }
}

final class AnnotationCanvasView: NSView {
    let session: AnnotationSession
    var interactive = false {
        didSet {
            if !interactive { label?.commit() }
            window?.invalidateCursorRects(for: self)
        }
    }
    var label: AnnotationLabelEditor?

    init(session: AnnotationSession) {
        self.session = session
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Global AppKit points to this view's own.
    var origin: CGPoint { window?.frame.origin ?? .zero }

    func invalidate(_ global: CGRect?) {
        guard let global else { return needsDisplay = true }
        setNeedsDisplay(global.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -2, dy: -2))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let o = origin
        let marks = session.shown + [session.drawing].compactMap { $0 }
        AnnotationPainter.draw(marks, at: .infinity, in: ctx, scale: 1) { CGPoint(x: $0.x - o.x, y: $0.y - o.y) }
    }

    // MARK: - Mouse

    private var cursor: NSCursor { session.tool == .text ? .iBeam : .crosshair }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited,
                                                              .cursorUpdate], owner: self))
    }

    /// Slice isn't the active app while recording, so cursor rects alone don't apply; set it as the pointer moves too.
    override func cursorUpdate(with event: NSEvent) { if interactive { cursor.set() } }
    override func mouseEntered(with event: NSEvent) { if interactive { cursor.set() } }
    override func mouseMoved(with event: NSEvent) { if interactive { cursor.set() } }

    override func resetCursorRects() {
        if interactive { addCursorRect(bounds, cursor: cursor) }
    }

    private func global(_ event: NSEvent) -> CGPoint {
        let p = event.locationInWindow
        return CGPoint(x: p.x + origin.x, y: p.y + origin.y)
    }

    override func mouseDown(with event: NSEvent) {
        guard interactive else { return }
        cursor.set()
        if let label {
            label.commit()
            return
        }
        if session.tool == .text {
            beginLabel(at: global(event))
        } else {
            session.begin(at: global(event), time: AnnotationSession.time(of: event))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard interactive, label == nil else { return }
        session.extend(to: global(event), time: AnnotationSession.time(of: event), constrained: event.modifierFlags.contains(.shift))
    }

    /// Right-click while drawing: tools, colours and sizes right where the pointer is.
    override func rightMouseDown(with event: NSEvent) {
        guard interactive else { return }
        label?.commit()
        session.finish()
        NSMenu.popUpContextMenu(toolMenu(), with: event, for: self)
    }

    override func mouseUp(with event: NSEvent) {
        guard interactive, label == nil else { return }
        session.extend(to: global(event), time: AnnotationSession.time(of: event), constrained: event.modifierFlags.contains(.shift))
        session.finish()
    }
}
