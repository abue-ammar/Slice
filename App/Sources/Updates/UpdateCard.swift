//
//  UpdateCard.swift
//  Slice
//
//  Created by rit3zh CX on 10/24/26.
//

import Combine
import SwiftUI

/// The update card at the top right of the screen Slice is on, like a notification. It never takes focus, goes away
/// while another app is in front or while recording, and comes back when that's over.
@MainActor
final class UpdateCardPanel {
    static let shared = UpdateCardPanel()

    private var panel: NSPanel?
    private var watch: AnyCancellable?
    private var wanted = false

    func start() {
        let updater = Updater.shared
        let center = NotificationCenter.default
        let active = Publishers.Merge(center.publisher(for: NSApplication.didBecomeActiveNotification).map { _ in true },
                                      center.publisher(for: NSApplication.didResignActiveNotification).map { _ in false })
            .prepend(NSApp.isActive)
        watch = updater.$cardShown
            .combineLatest(updater.$phase.map(\.showsCard), AppModel.shared.$recording.map { $0 == nil }, active)
            .map { $0 && $1 && $2 && $3 }
            .removeDuplicates()
            .sink { [weak self] in $0 ? self?.show() : self?.hide() }
    }

    private func show() {
        wanted = true
        let panel = panel ?? make()
        let target = frame(for: panel)
        panel.setFrame(target.offsetBy(dx: 0, dy: 6), display: false)
        if !panel.isVisible { panel.alphaValue = 0 }
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    private func hide() {
        wanted = false
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.16; panel.animator().alphaValue = 0 }) { [weak self, weak panel] in
            MainActor.assumeIsolated { if self?.wanted == false { panel?.orderOut(nil) } }
        }
    }

    private func make() -> NSPanel {
        let host = CardHostingView(rootView: UpdateCard())
        host.sizingOptions = [.intrinsicContentSize]
        let panel = CardPanel(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = host
        host.resized = { [weak self, weak panel] in
            guard let self, let panel, panel.isVisible else { return }
            panel.setFrame(frame(for: panel), display: true)
        }
        self.panel = panel
        return panel
    }

    /// Pinned to the top right, so the card grows and shrinks downwards.
    private func frame(for panel: NSPanel) -> CGRect {
        let size = panel.contentView?.fittingSize ?? panel.frame.size
        let main = AppModel.mainWindow.flatMap { $0.isVisible ? $0.screen : nil }
        guard let area = (main ?? NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame else { return panel.frame }
        return CGRect(x: area.maxX - size.width, y: area.maxY - size.height, width: size.width, height: size.height)
    }
}

private final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// Buttons in a panel that never becomes key still act on the first click.
private final class CardHostingView: NSHostingView<UpdateCard> {
    var resized: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.resized?() }
    }
}

extension Updater.Phase {
    var showsCard: Bool {
        switch self {
        case .available, .downloading, .preparing, .ready, .installing, .failed: true
        case .idle, .checking, .upToDate: false
        }
    }
}

// MARK: - Card

struct UpdateCard: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if case .installing = updater.phase { ProgressView().controlSize(.small) }
            }
            content
            actions
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
        .modifier(BarSurface())
        .padding(18)
        .environment(\.colorScheme, .dark)
        // The panel never becomes key, which would otherwise draw the buttons greyed out like a window in the back.
        .environment(\.controlActiveState, .key)
        .tint(Theme.accent)
    }

    private var release: Updater.Release? { updater.phase.release }

    private var title: String {
        switch updater.phase {
        case .available: "Update available"
        case .downloading: "Downloading update"
        case .preparing: "Preparing update"
        case .ready: "Update ready to install"
        case .installing: "Installing update"
        case .failed: release == nil ? "Couldn't check for updates" : "Couldn't update Slice"
        case .idle, .checking, .upToDate: ""
        }
    }

    private var detail: String {
        let name = release.map { "Slice \($0.version)" } ?? ""
        switch updater.phase {
        case let .available(release):
            return release.date.map { "\(name) · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? name
        case let .downloading(_, received, total) where total > 0:
            return "\(name) · \(received * 100 / total)% of \(Self.size(total))"
        case .ready:
            return updater.busyReason ?? "\(name) · Installs with a quick relaunch"
        case .installing:
            return "Slice relaunches in a moment."
        case let .failed(message, _):
            return message
        default:
            return name
        }
    }

    @ViewBuilder private var content: some View {
        switch updater.phase {
        case let .available(release) where !release.notes.isEmpty:
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(release.notes.prefix(3).enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle().fill(.tertiary).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0.height + 0.5 }
                        Text((try? AttributedString(markdown: line)) ?? AttributedString(line))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if release.notes.count > 3, let page = release.page {
                    Link("See all changes", destination: page).font(.system(size: 11))
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        case let .downloading(_, received, total):
            if total > 0 {
                ProgressView(value: Double(received), total: Double(total))
            } else {
                ProgressView().progressViewStyle(.linear)
            }
        case .preparing:
            ProgressView().progressViewStyle(.linear)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var actions: some View {
        switch updater.phase {
        case .available:
            HStack(spacing: 8) {
                Button("Skip This Version") { updater.skip() }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Later") { updater.later() }
                Button("Update Now") { updater.updateNow() }.buttonStyle(.borderedProminent)
            }
        case .downloading, .preparing:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Hide") { updater.hide() }
                if updater.canCancel { Button("Cancel") { updater.cancel() } }
            }
        case .ready:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Later") { updater.later() }
                Button("Install & Relaunch") { updater.installAndRelaunch() }
                    .buttonStyle(.borderedProminent)
                    .disabled(updater.busyReason != nil)
            }
        case .failed:
            HStack(spacing: 8) {
                Spacer(minLength: 0)
                Button("Later") { updater.later() }
                Button("Try Again") { updater.retry() }.buttonStyle(.borderedProminent)
            }
        default:
            EmptyView()
        }
    }

    static func size(_ bytes: UInt64) -> String { ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file) }
}
