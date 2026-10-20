//
//  FloatingDrawBar.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import SwiftUI

/// The drawing tools when drawing's turned on outside a recording, where the capture bar isn't there to hold them.
/// Top centre of the display the pointer's on, above the canvases, and it never takes focus from the app in front.
final class FloatingDrawBarPanel: NSPanel {
    private let session: AnnotationSession

    override var canBecomeKey: Bool { false }

    init(session: AnnotationSession) {
        self.session = session
        let host = FirstClickHostingView(rootView: FloatingDrawBar(session: session))
        super.init(contentRect: CGRect(origin: .zero, size: host.fittingSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: AnnotationCanvasPanel.level.rawValue + 2)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        appearance = NSAppearance(named: .darkAqua)
        contentView = host
    }

    @MainActor
    func present() {
        let p = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(p) }) ?? NSScreen.main else { return }
        let size = contentView?.fittingSize ?? frame.size
        let area = screen.visibleFrame
        setFrame(CGRect(x: area.midX - size.width / 2, y: area.maxY - size.height - 8, width: size.width, height: size.height),
                 display: true)
        if !isVisible {
            alphaValue = 0
            orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; animator().alphaValue = 1 }
        }
    }

    @MainActor
    func dismiss() {
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.14; animator().alphaValue = 0 }) { [weak self] in
            MainActor.assumeIsolated { self?.close() }
        }
    }
}

private struct FloatingDrawBar: View {
    @ObservedObject var session: AnnotationSession

    var body: some View {
        HStack(spacing: 0) {
            DrawToggle(session: session)
            AnnotationTools(session: session, trailingDivider: false)
        }
        .padding(.horizontal, 10)
        .frame(height: 60)
        .modifier(BarSurface())
        .padding(18)
        .environment(\.colorScheme, .dark)
    }
}

/// Buttons in a panel that never becomes key still act on the first click.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
