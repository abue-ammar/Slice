//
//  WindowPicker.swift
//  Slice
//
//  Created by rit3zh CX on 10/5/26.
//

import AppKit
import SwiftUI

@MainActor
final class WindowPicker: ObservableObject {
    static let shared = WindowPicker()

    struct Target: Equatable {
        let id: CGWindowID
        let frame: CGRect
        let app: String
        let icon: NSImage?

        static func == (a: Target, b: Target) -> Bool { a.id == b.id && a.frame == b.frame && a.app == b.app }
    }

    @Published private(set) var target: Target?
    @Published private(set) var selected: CGWindowID?

    var recordable: Set<CGWindowID> = [] { didSet { update(force: true) } }
    var onPick: (CGWindowID) -> Void = { _ in }
    var onRecord: (CGWindowID) -> Void = { _ in }
    var onUnknown: () -> Void = {}

    private var previewed: CGWindowID?
    private var panels: [PickerPanel] = []
    private var timer: Timer?
    private var lastPointer: CGPoint?
    private var ticks = 0
    private var lastUnknown: Date = .distantPast
    private var shown = false

    func select(_ id: CGWindowID?) {
        guard selected != id else { return }
        selected = id
        update(force: true)
    }

    func preview(_ id: CGWindowID, _ on: Bool) {
        if on { previewed = id } else if previewed == id { previewed = nil }
        update(force: true)
    }

    func clearPreview() {
        guard previewed != nil else { return }
        previewed = nil
        update(force: true)
    }

    func present(_ on: Bool) {
        guard on != shown else { return }
        shown = on
        if on {
            makePanels()
            let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.update(force: false) }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
            update(force: true)
            panels.forEach { $0.alphaValue = 1; $0.orderFrontRegardless() }
        } else {
            timer?.invalidate()
            timer = nil
            previewed = nil
            let leaving = panels
            panels = []
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                leaving.forEach { $0.animator().alphaValue = 0 }
            } completionHandler: {
                MainActor.assumeIsolated {
                    leaving.forEach { $0.orderOut(nil) }
                    if !self.shown { self.target = nil }
                }
            }
        }
    }

    private func makePanels() {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map { screen in
            let panel = PickerPanel(frame: screen.frame)
            let host = FirstClickHostingView(rootView: WindowPickerOverlay(picker: self, screen: screen.frame))
            host.frame = CGRect(origin: .zero, size: screen.frame.size)
            host.autoresizingMask = [.width, .height]
            panel.contentView = host
            return panel
        }
    }

    // MARK: Tracking

    private func update(force: Bool) {
        guard shown else { return }
        let pointer = NSEvent.mouseLocation
        ticks += 1
        guard force || pointer != lastPointer || ticks % 15 == 0 else { return }
        lastPointer = pointer
        if panels.map(\.frame) != NSScreen.screens.map(\.frame) {
            makePanels()
            panels.forEach { $0.orderFrontRegardless() }
        }

        let onScreen = Self.onScreenWindows()
        var pointed: CGWindowID?
        if !overOwnWindow(pointer), let hit = onScreen.first(where: { $0.frame.contains(pointer) }) {
            if recordable.contains(hit.id) {
                pointed = hit.id
            } else if Date().timeIntervalSince(lastUnknown) > 1 {
                lastUnknown = Date()
                onUnknown()
            }
        }

        let next = [previewed, pointed, selected].lazy.compactMap { id in onScreen.first { $0.id == id } }.first
        let target = next.map { w in
            let app = NSRunningApplication(processIdentifier: w.pid)
            return Target(id: w.id, frame: w.frame, app: app?.localizedName ?? w.owner, icon: app?.icon)
        }
        if target != self.target { self.target = target }
        let live = target.map { $0.frame.contains(pointer) && pointed == $0.id } ?? false
        for panel in panels where panel.ignoresMouseEvents == live { panel.ignoresMouseEvents = !live }
    }

    private func overOwnWindow(_ p: CGPoint) -> Bool {
        NSApp.windows.contains { w in
            w.isVisible && !(w is PickerPanel) && w.alphaValue > 0 && w.frame.contains(p)
        }
    }

    private struct OnScreen {
        let id: CGWindowID
        let pid: pid_t
        let owner: String
        let frame: CGRect
    }

    private static func onScreenWindows() -> [OnScreen] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        let primary = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  let id = info[kCGWindowNumber as String] as? CGWindowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t, pid != me,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let r = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return OnScreen(id: id, pid: pid, owner: info[kCGWindowOwnerName as String] as? String ?? "",
                            frame: CGRect(x: r.minX, y: primary - r.maxY, width: r.width, height: r.height))
        }
    }
}

private final class PickerPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct WindowPickerOverlay: View {
    @ObservedObject var picker: WindowPicker
    let screen: CGRect

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let target = picker.target, target.frame.intersects(screen) {
                let r = CGRect(x: target.frame.minX - screen.minX, y: screen.maxY - target.frame.maxY,
                               width: target.frame.width, height: target.frame.height)
                WindowHighlight(target: target, selected: picker.selected == target.id,
                                pick: { picker.onPick(target.id) }, record: { picker.onRecord(target.id) })
                    .frame(width: r.width, height: r.height)
                    .offset(x: r.minX, y: r.minY)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea()
        .animation(.smooth(duration: 0.3), value: picker.target)
        .environment(\.colorScheme, .dark)
    }
}

private struct WindowHighlight: View {
    let target: WindowPicker.Target
    let selected: Bool
    let pick: () -> Void
    let record: () -> Void

    private static let tint = Color(red: 0.08, green: 0.22, blue: 0.48)
    private static let accent = Color(red: 0.16, green: 0.47, blue: 1.0)

    private var radius: CGFloat {
        if #available(macOS 26, *) { 16 } else { 10 }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(Self.tint.opacity(0.62))
            shape.strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
            ViewThatFits(in: .vertical) {
                card(icon: 88, title: 28, spacing: 10)
                card(icon: 44, title: 15, spacing: 6)
                recordButton
            }
            .padding(12)
            .id(target.id)
            .transition(.opacity)
        }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture(perform: pick)
    }

    private func card(icon: CGFloat, title: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            if let image = target.icon {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: icon, height: icon)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
            }
            VStack(spacing: 4) {
                Text(target.app)
                    .font(.system(size: title, weight: .bold, design: .rounded))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 11, weight: .semibold)) }
                    Text("\(Int(target.frame.width)) × \(Int(target.frame.height))")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            recordButton.padding(.top, spacing / 2)
        }
    }

    private var recordButton: some View {
        Button(action: record) {
            HStack(spacing: 7) {
                Image(systemName: "record.circle").font(.system(size: 14, weight: .semibold))
                Text("Start recording").font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Self.accent))
            .contentShape(Rectangle())
        }
        .buttonStyle(RecordPressStyle())
        .fixedSize()
    }
}

private struct RecordPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.06 : 0)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.smooth(duration: 0.15), value: configuration.isPressed)
    }
}
