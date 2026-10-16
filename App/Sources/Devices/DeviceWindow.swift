//
//  DeviceWindow.swift
//  Slice
//
//  Created by rit3zh CX on 10/5/26.
//

import AppKit
import SliceCore
import SwiftUI

/// Borderless windows can't become key by default; this one should, for its menu and keyboard shortcuts.
final class DeviceMockupWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DeviceWindowController: NSWindowController, NSWindowDelegate {
    static let identifier = NSUserInterfaceItemIdentifier("device-window")
    static let minimumHeight: CGFloat = 320

    private weak var connection: DeviceConnection?
    private var fittedCanvas: CGSize?

    init(connection: DeviceConnection) {
        self.connection = connection
        let window = DeviceMockupWindow(contentRect: CGRect(x: 0, y: 0, width: 390, height: 800), styleMask: [.borderless],
                                        backing: .buffered, defer: false)
        window.identifier = Self.identifier
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovable = true
        window.collectionBehavior = [.fullScreenAuxiliary]
        let host = NSHostingView(rootView: DeviceWindowView(connection: connection))
        host.sizingOptions = []
        window.contentView = host
        window.setFrameAutosaveName("DeviceWindow-\(connection.id)")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        if !window.setFrameUsingName("DeviceWindow-\(connection.id)") { window.center() }
        floatsOnTop = UserDefaults.standard.object(forKey: "device.floatsOnTop") as? Bool ?? true
        updateTitle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    static func isDeviceWindow(_ window: NSWindow) -> Bool { window.identifier == identifier }

    static let windowsDidChange = Notification.Name("DeviceWindowsDidChange")

    static func windowNumbers() -> Set<CGWindowID> {
        Set(NSApp.windows.filter { isDeviceWindow($0) && $0.windowNumber > 0 }.map { CGWindowID($0.windowNumber) })
    }

    func updateTitle() {
        guard let window, let connection else { return }
        window.title = connection.info.name
    }

    var floatsOnTop: Bool {
        get { window?.level == .floating }
        set {
            window?.level = newValue ? .floating : .normal
            UserDefaults.standard.set(newValue, forKey: "device.floatsOnTop")
        }
    }

    // MARK: - Size

    func fit(canvas: CGSize, animated: Bool = false) {
        guard let window, canvas.width > 0, canvas.height > 0 else { return }
        window.contentAspectRatio = canvas
        guard fittedCanvas.map({ abs($0.width / $0.height - canvas.width / canvas.height) > 0.02 }) ?? true else { return }
        fittedCanvas = canvas
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size: CGSize
        if canvas.width > canvas.height {
            let w = min(max(window.frame.height, 640), visible.width * 0.8)
            size = CGSize(width: w, height: w * canvas.height / canvas.width)
        } else {
            let h = min(max(window.frame.height, 560), visible.height * 0.85)
            size = CGSize(width: h * canvas.width / canvas.height, height: h)
        }
        Self.setFrame(of: window, size: size, around: CGPoint(x: window.frame.midX, y: window.frame.midY), animated: animated)
    }

    func setScale(_ fraction: CGFloat) {
        guard let window, let canvas = fittedCanvas else { return }
        let points = fraction / window.backingScaleFactor
        Self.setFrame(of: window, size: CGSize(width: canvas.width * points, height: canvas.height * points),
                      around: CGPoint(x: window.frame.midX, y: window.frame.midY))
    }

    static func setFrame(of window: NSWindow, size: CGSize, around centre: CGPoint, animated: Bool = false) {
        let s = clamp(size, window)
        let frame = CGRect(x: centre.x - s.width / 2, y: centre.y - s.height / 2, width: s.width, height: s.height)
        guard animated, window.isVisible else { return place(window, frame) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DeviceMorph.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            window.invalidateCursorRects(for: window.contentView ?? NSView())
        }
    }

    static func setFrame(of window: NSWindow, size: CGSize, anchor: CGPoint, corner: PhonePreviewNSView.Corner) {
        let s = clamp(size, window)
        let x = corner == .topLeft || corner == .bottomLeft ? anchor.x - s.width : anchor.x
        let y = corner == .topLeft || corner == .topRight ? anchor.y : anchor.y - s.height
        place(window, CGRect(x: x, y: y, width: s.width, height: s.height))
    }

    private static func clamp(_ size: CGSize, _ window: NSWindow) -> CGSize {
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        let aspect = size.width / max(size.height, 1)
        var h = min(max(size.height, minimumHeight), visible.height * 1.5)
        if h * aspect < 160 { h = 160 / aspect }
        return CGSize(width: (h * aspect).rounded(), height: h.rounded())
    }

    private static func place(_ window: NSWindow, _ frame: CGRect) {
        window.setFrame(frame, display: true)
        window.invalidateCursorRects(for: window.contentView ?? NSView())
    }

    func canvasRectOnScreen(layout: DeviceLayout) -> CGRect? {
        guard let window, window.isVisible, !window.isMiniaturized, let view = window.contentView else { return nil }
        let local = layout.fitted(in: view.bounds.size)
        let inWindow = view.convert(CGRect(x: local.minX, y: view.isFlipped ? local.minY : view.bounds.height - local.maxY,
                                           width: local.width, height: local.height), to: nil)
        let screen = window.convertToScreen(inWindow)
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.maxY
        return CGRect(x: screen.minX, y: primaryHeight - screen.maxY, width: screen.width, height: screen.height)
    }

    // MARK: - Menu

    func makeMenu() -> NSMenu? {
        guard let connection else { return nil }
        let catalog = DeviceManager.shared.catalog
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionItem(connection.info.name, enabled: false) {})
        menu.addItem(.separator())
        if let frame = connection.frame, !frame.isFrameless {
            for color in catalog.colors(for: frame.model) {
                menu.addItem(ActionItem(color.rawValue, checked: color == frame.color) { connection.useFrame(model: frame.model, color: color) })
            }
        }
        let other = NSMenu()
        for model in catalog.models {
            let colors = NSMenu()
            for color in catalog.colors(for: model) {
                colors.addItem(ActionItem(color.rawValue) { connection.useFrame(model: model, color: color) })
            }
            let item = NSMenuItem(title: model, action: nil, keyEquivalent: "")
            item.submenu = colors
            other.addItem(item)
        }
        let otherItem = NSMenuItem(title: "Other Frame", action: nil, keyEquivalent: "")
        otherItem.submenu = other
        menu.addItem(otherItem)
        menu.addItem(ActionItem("No Frame", checked: connection.frame?.isFrameless == true) { connection.useFrame(model: "") })
        menu.addItem(ActionItem("Automatic Frame", enabled: !connection.frameChoiceIsAutomatic) { connection.useFrame(model: nil) })
        menu.addItem(.separator())
        let sizes = NSMenu()
        for (title, fraction) in [("Actual Pixels", 1.0), ("Half Size", 0.5), ("Third Size", 0.34)] as [(String, CGFloat)] {
            sizes.addItem(ActionItem(title) { [weak self] in self?.setScale(fraction) })
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        menu.addItem(ActionItem("Float on Top", checked: floatsOnTop) { [weak self] in self?.floatsOnTop.toggle() })
        menu.addItem(ActionItem("Play iPhone Sound", checked: connection.playsSound) { connection.playsSound.toggle() })
        menu.addItem(.separator())
        menu.addItem(ActionItem("Hide") { [weak self] in self?.window?.orderOut(nil) })
        return menu
    }
}

private final class ActionItem: NSMenuItem {
    private let run: () -> Void

    init(_ title: String, checked: Bool = false, enabled: Bool = true, _ run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
        isEnabled = enabled
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}

struct DeviceWindowView: View {
    @ObservedObject var connection: DeviceConnection

    private var streaming: Bool { connection.info.state == .streaming }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PhonePreview(source: connection.preview, movesWindow: true,
                             menu: { [weak connection] in connection?.windowMenu() })
                    .opacity(connection.frame == nil ? 0 : 1)
                if !streaming {
                    DeviceStatusCard(state: connection.info.state, name: connection.info.name)
                        .frame(maxWidth: geo.size.width * 0.72)
                        .allowsHitTesting(connection.info.state == .permissionDenied)
                        .transition(.opacity)
                }
            }
        }
        .animation(.snappy(duration: 0.25), value: connection.info.state)
        .environment(\.colorScheme, .dark)
    }
}

struct DeviceStatusCard: View {
    let state: DeviceState
    let name: String

    var body: some View {
        VStack(spacing: 10) {
            if state == .connecting {
                ProgressView()
            } else {
                Image(systemName: state.systemImage)
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(.secondary)
            }
            Text(name).font(.caption.weight(.medium)).foregroundStyle(.secondary)
            Text(state.title).font(.headline)
            if !state.detail.isEmpty {
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if state == .permissionDenied {
                Button("Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                }
                .controlSize(.small)
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
