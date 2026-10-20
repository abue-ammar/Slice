//
//  AnnotationController.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import AppKit
import Carbon.HIToolbox
import Combine
import SliceCore

/// Drawing over the screen: a canvas over every display, the shortcut that turns drawing on and off from anywhere,
/// and the keys that work while it's on. Off, the canvases let every click through and only show the marks.
/// Marks drawn before recording are in the take from its first frame; outside a recording, turning drawing off
/// wipes them, as a presenter's pen does.
@MainActor
final class AnnotationController {
    static let shared = AnnotationController()

    /// The user's shortcut for drawing, set in Settings.
    private(set) var shortcut = DrawShortcut.saved
    static var toggleKeys: [String] { shared.shortcut.keys }
    static var toggleLabel: String { toggleKeys.joined() }
    static let toolKeys = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7]
    /// P, H, L, A, R, O, T: the first letter of each tool, as its button's tooltip shows.
    static let toolLetters = [kVK_ANSI_P, kVK_ANSI_H, kVK_ANSI_L, kVK_ANSI_A, kVK_ANSI_R, kVK_ANSI_O, kVK_ANSI_T]

    let session = AnnotationSession()
    private var panels: [CGDirectDisplayID: AnnotationCanvasPanel] = [:]
    private var toolbar: FloatingDrawBarPanel?
    private var toggleKey: UInt32?
    private var modeKeys: [UInt32] = []
    private var watches: Set<AnyCancellable> = []
    private var screenObserver: NSObjectProtocol?
    private var controlsWatch: Timer?
    /// A recording is under way: marks stay when drawing's turned off, and the capture bar holds the tools.
    private(set) var isRecording = false
    /// False while recording an iPhone, whose picture isn't the Mac's screen.
    private(set) var isAvailable = true

    private init() {
        session.onChange = { [weak self] rect in self?.panels.values.forEach { $0.canvas.invalidate(rect) } }
        session.$isActive.removeDuplicates().dropFirst().sink { [weak self] in self?.activeChanged($0) }.store(in: &watches)
        session.$isTyping.removeDuplicates().dropFirst().sink { [weak self] typing in
            guard let self, session.isActive else { return }
            if typing { releaseModeKeys() } else { holdModeKeys() }
        }.store(in: &watches)
    }

    /// Registers the shortcut for as long as Slice runs.
    func install() {
        guard toggleKey == nil else { return }
        toggleKey = HotKeys.shared.register(shortcut.combo) { [weak self] in self?.toggleDrawing() }
    }

    /// Switches to `next` and keeps it, or leaves the shortcut as it was and returns false if another app holds `next`.
    @discardableResult
    func setShortcut(_ next: DrawShortcut) -> Bool {
        suspendShortcut()
        guard let key = HotKeys.shared.register(next.combo, action: { [weak self] in self?.toggleDrawing() }) else {
            install()
            return false
        }
        toggleKey = key
        shortcut = next
        next.save()
        return true
    }

    /// Off while a new one's being typed in Settings, so pressing the current one there doesn't start drawing.
    func suspendShortcut() {
        HotKeys.shared.unregister(toggleKey)
        toggleKey = nil
    }

    func toggleDrawing() {
        guard isAvailable else { return }
        session.isActive.toggle()
    }

    /// Keys the pointer log should leave out: the shortcut itself, and everything typed while drawing.
    func swallows(_ event: NSEvent) -> Bool {
        session.isActive || shortcut.combo.matches(event)
    }

    // MARK: - Recording

    func recordingStarted(device: Bool) {
        isRecording = true
        isAvailable = !device
        if device {
            session.isActive = false
            session.reset()
            hideCanvases()
        }
        toolbar?.dismiss()
        toolbar = nil
    }

    /// Stop was pressed: the drawing goes away now, while what was drawn stays for the take still being saved.
    func recordingStopping() {
        session.isActive = false
        hideCanvases()
    }

    func recordingEnded() {
        isRecording = false
        isAvailable = true
        session.isActive = false
        session.reset()
        hideCanvases()
    }

    // MARK: - Canvases

    private func activeChanged(_ active: Bool) {
        watchControls(active)
        if active {
            showCanvases()
            placeBar()
        } else {
            session.finish()
            if !isRecording {
                session.reset()
                hideCanvases()
            }
        }
        panels.values.forEach { setInteractive($0, active) }
        if active { holdModeKeys() } else { releaseModeKeys() }
        (active ? session.tool == .text ? NSCursor.iBeam : .crosshair : .arrow).set()
        if active, !isRecording {
            toolbar = toolbar ?? FloatingDrawBarPanel(session: session)
            toolbar?.present()
        } else {
            toolbar?.dismiss()
            toolbar = nil
        }
    }

    private func showCanvases() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.layOut() }
        }
        layOut()
        placeBar()
    }

    private func hideCanvases() {
        screenObserver.map(NotificationCenter.default.removeObserver)
        screenObserver = nil
        panels.values.forEach { $0.close() }
        panels = [:]
        toolbar?.dismiss()
        toolbar = nil
        releaseModeKeys()
        placeBar()
    }

    /// A canvas per display, following displays as they come, go, move or change resolution. Marks are kept in
    /// global points, so they stay on what they were drawn over.
    private func layOut() {
        var kept: [CGDirectDisplayID: AnnotationCanvasPanel] = [:]
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let panel = panels.removeValue(forKey: id) ?? AnnotationCanvasPanel(screen: screen, session: session)
            panel.place(on: screen)
            setInteractive(panel, session.isActive)
            panel.orderFrontRegardless()
            kept[id] = panel
        }
        panels.values.forEach { $0.close() }
        panels = kept
        toolbar?.present()
    }

    // MARK: - Reaching the tools

    /// While drawing, the canvases step aside wherever the tools are, so a click on them presses the button instead of
    /// drawing a dot on it. Window levels alone can't promise that: SwiftUI can put the bar's level back.
    private func watchControls(_ on: Bool) {
        controlsWatch?.invalidate()
        controlsWatch = nil
        guard on else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePassThrough() }
        }
        RunLoop.main.add(timer, forMode: .common)
        controlsWatch = timer
        updatePassThrough()
    }

    private func updatePassThrough() {
        guard session.isActive, NSEvent.pressedMouseButtons == 0 else { return }
        if let bar = AppModel.captureBarWindow, bar.isVisible, bar.level != barLevel { bar.level = barLevel }
        let p = NSEvent.mouseLocation
        let overControls = controlRects.contains { $0.contains(p) }
        for panel in panels.values where panel.ignoresMouseEvents != overControls {
            panel.ignoresMouseEvents = overControls
        }
    }

    /// The tool surfaces on screen, in global points.
    private var controlRects: [CGRect] {
        var rects: [CGRect] = []
        if let toolbar, toolbar.isVisible { rects.append(toolbar.frame) }
        if let bar = AppModel.captureBarWindow, bar.isVisible {
            if isRecording {
                let w = LiveBar.drawingWidth, h: CGFloat = 72
                rects.append(CGRect(x: bar.frame.midX - w / 2, y: bar.frame.midY - h / 2, width: w, height: h).insetBy(dx: -6, dy: -6))
            } else {
                rects.append(bar.frame.insetBy(dx: Bar.inset - 6, dy: Bar.inset - 6))
            }
        }
        return rects
    }

    private func setInteractive(_ panel: AnnotationCanvasPanel, _ on: Bool) {
        panel.ignoresMouseEvents = !on
        panel.canvas.interactive = on
    }

    /// The capture bar sits above the canvases so it can still be used while drawing.
    var barLevel: NSWindow.Level {
        screenObserver != nil ? NSWindow.Level(rawValue: AnnotationCanvasPanel.level.rawValue + 1) : .floating
    }

    private func placeBar() {
        AppModel.captureBarWindow?.level = barLevel
    }

    // MARK: - Keys while drawing

    private func holdModeKeys() {
        guard modeKeys.isEmpty, !session.isTyping else { return }
        let hk = HotKeys.shared
        var keys: [UInt32?] = [
            hk.register(.init(keyCode: kVK_Escape, modifiers: [])) { [weak self] in self?.session.isActive = false },
            hk.register(.init(keyCode: kVK_ANSI_Z, modifiers: .command)) { [weak self] in self?.session.undo() },
            hk.register(.init(keyCode: kVK_Delete, modifiers: .command)) { [weak self] in self?.session.clear() },
        ]
        for (i, tool) in Annotation.Tool.allCases.enumerated() {
            for key in [Self.toolKeys[i], Self.toolLetters[i]] {
                keys.append(hk.register(.init(keyCode: key, modifiers: [])) { [weak self] in self?.session.tool = tool })
            }
        }
        modeKeys = keys.compactMap { $0 }
    }

    private func releaseModeKeys() {
        modeKeys.forEach { HotKeys.shared.unregister($0) }
        modeKeys = []
    }
}
