//
//  EditorTitleBar.swift
//  Slice
//
//  Created by rit3zh CX on 10/8/26.
//

import AppKit
import SliceCore
import SwiftUI

struct EditorTitleBar: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var editor: EditorModel
    let isExporting: Bool
    let openPalette: () -> Void
    let openExport: () -> Void
    @State private var lightsInset: CGFloat?

    static let height: CGFloat = 52

    var body: some View {
        ZStack {
            title
            HStack(spacing: 0) {
                leading
                Spacer(minLength: 16)
                trailing
            }
            .padding(.leading, lightsInset ?? 14)
            .padding(.trailing, 12)
        }
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background { DragArea() }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.stroke).frame(height: 1)
        }
        .background(TrafficLights(height: Self.height) { lightsInset = $0 })
    }

    private var title: some View {
        Text("\(Text(editor.project.name).foregroundStyle(.primary))\(Text(".\(ProjectBundle.fileExtension)").foregroundStyle(.tertiary))")
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: 320)
            .allowsHitTesting(false)
    }

    private var leading: some View {
        HStack(spacing: 2) {
            Button {
                editor.close()
                model.show(.home)
            } label: { Label("Projects", systemImage: "folder") }
                .help("Back to projects")
            Button {
                importInto(editor)
            } label: { Label("Add Clip", systemImage: "plus.rectangle.on.rectangle") }
                .help("Add a pre-recorded video to the end of this project")
            Button {
                editor.close()
                model.newRecording(appendTo: editor)
            } label: { Label("Record Take", systemImage: "record.circle") }
                .help("Record another take onto the end of this project")
        }
        .buttonStyle(IconButtonStyle(size: 30, iconSize: 14))
        .disabled(isExporting)
    }

    private var trailing: some View {
        HStack(spacing: 2) {
            Button(action: openPalette) { Label("Commands", systemImage: "command") }
                .help("Commands (⌘K)")
            BarDivider()
            Button { editor.undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }
                .disabled(!editor.canUndo).help("Undo (⌘Z)")
            Button { editor.redo() } label: { Label("Redo", systemImage: "arrow.uturn.forward") }
                .disabled(!editor.canRedo).help("Redo (⇧⌘Z)")
            BarDivider()
            Button {
                editor.autoZoom()
            } label: { Label("Smart Zoom", systemImage: "sparkle.magnifyingglass") }
                .buttonStyle(QuietButtonStyle())
                .help(editor.hasPointerLog ? "Find the moments worth zooming into (keeps zooms you've edited)"
                    : "These takes have no pointer recording to analyse")
                .disabled(!editor.hasPointerLog || editor.smartZoomProgress != nil)
                .padding(.trailing, 6)
            Button(action: openExport) { Label("Export", systemImage: "square.and.arrow.up") }
                .buttonStyle(PillButtonStyle(prominent: true))
                .help("Export (⇧⌘E)")
        }
        .buttonStyle(IconButtonStyle(size: 30, iconSize: 14))
        .disabled(isExporting)
    }
}

private struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 8)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { QuietButtonBody(configuration: configuration) }
}

private struct QuietButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(hovering ? Theme.controlHover : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 && isEnabled }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

struct DragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .allowsWindowActivationEvents(true)
            .simultaneousGesture(TapGesture(count: 2).onEnded {
                guard let window = NSApp.keyWindow else { return }
                switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
                case "Minimize": window.miniaturize(nil)
                case "None": break
                default: window.zoom(nil)
                }
            })
    }
}

// MARK: - Window buttons

/// Centres the window's close, minimise and zoom buttons in a bar taller than the title bar while the bar is on screen,
/// and puts them back when it goes. AppKit lays the buttons out again whenever the window changes, so this follows.
struct TrafficLights: NSViewRepresentable {
    let height: CGFloat
    var leading: CGFloat? = nil
    let inset: (CGFloat?) -> Void

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.height = height
        probe.leading = leading
        probe.inset = inset
        return probe
    }

    func updateNSView(_ nsView: Probe, context: Context) { nsView.inset = inset }

    static func dismantleNSView(_ nsView: Probe, coordinator: ()) { nsView.detach() }

    final class Probe: NSView {
        var height: CGFloat = 52
        var leading: CGFloat?
        var inset: (CGFloat?) -> Void = { _ in }
        private var originalX: [ObjectIdentifier: CGFloat] = [:]
        private weak var attached: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var originalHeight: CGFloat?
        private var reported: CGFloat??
        private var applying = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window !== attached else { return }
            detach()
            guard let window else { return }
            attached = window
            let center = NotificationCenter.default
            let follow: (Notification.Name, AnyObject?) -> Void = { [unowned self] name, object in
                observers.append(center.addObserver(forName: name, object: object, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.apply() }
                })
            }
            for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didExitFullScreenNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
                follow(name, window)
            }
            observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.restore() }
            })
            for view in [container(of: window)].compactMap({ $0 }) + buttons(of: window) {
                view.postsFrameChangedNotifications = true
                follow(NSView.frameDidChangeNotification, view)
            }
            apply()
        }

        func detach() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            restore()
            attached = nil
        }

        private func buttons(of window: NSWindow) -> [NSButton] {
            [.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        }

        private func container(of window: NSWindow) -> NSView? {
            window.standardWindowButton(.closeButton)?.superview?.superview
        }

        private func apply() {
            guard !applying, let window = attached, let container = container(of: window), let frameView = container.superview else { return }
            if window.styleMask.contains(.fullScreen) {
                report(nil)
                return
            }
            applying = true
            defer { applying = false }
            if originalHeight == nil { originalHeight = container.frame.height }
            setHeight(height, of: container, in: frameView)
            let buttons = buttons(of: window)
            if leading != nil {
                for button in buttons where originalX[ObjectIdentifier(button)] == nil {
                    originalX[ObjectIdentifier(button)] = button.frame.origin.x
                }
            }
            let shift = leading.flatMap { leading in
                buttons.first.flatMap { originalX[ObjectIdentifier($0)] }.map { leading - $0 }
            }
            for button in buttons {
                guard let bar = button.superview else { continue }
                let y = ((bar.bounds.height - button.frame.height) / 2).rounded()
                let x = shift.map { (originalX[ObjectIdentifier(button)] ?? button.frame.origin.x) + $0 } ?? button.frame.origin.x
                if button.frame.origin != NSPoint(x: x, y: y) { button.setFrameOrigin(NSPoint(x: x, y: y)) }
            }
            if let last = buttons.last, let bar = last.superview {
                report(bar.convert(last.frame, to: nil).maxX + 14)
            }
        }

        private func restore() {
            guard let window = attached, let originalHeight, let container = container(of: window),
                  let frameView = container.superview else { return }
            applying = true
            defer { applying = false }
            self.originalHeight = nil
            setHeight(originalHeight, of: container, in: frameView)
            for button in buttons(of: window) {
                guard let bar = button.superview else { continue }
                let x = originalX[ObjectIdentifier(button)] ?? button.frame.origin.x
                button.setFrameOrigin(NSPoint(x: x, y: ((bar.bounds.height - button.frame.height) / 2).rounded()))
            }
            originalX = [:]
            frameView.needsLayout = true
            report(nil)
        }

        private func setHeight(_ height: CGFloat, of container: NSView, in frameView: NSView) {
            var frame = container.frame
            frame.size.height = height
            frame.origin.y = frameView.isFlipped ? 0 : frameView.bounds.height - height
            if container.frame != frame { container.frame = frame }
        }

        private func report(_ value: CGFloat?) {
            guard reported != .some(value) else { return }
            reported = .some(value)
            let inset = inset
            DispatchQueue.main.async { inset(value) }
        }
    }
}
