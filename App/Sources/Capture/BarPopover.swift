//
//  BarPopover.swift
//  Slice
//
//  Created by rit3zh CX on 10/1/26.
//

import SwiftUI

/// `preferredColorScheme` doesn't reach a popover's own window, so its AppKit controls (segmented picker, switches)
/// still drew light: white selected segment under white text. Pinning the window's appearance fixes them and the glass.
/// The bar never takes focus, so its popovers opened unfocused and drew their controls grey until clicked; each one is
/// made key as it opens so they show the accent straight away.
struct BarPopoverWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.appearance = NSAppearance(named: .darkAqua)
            DispatchQueue.main.async { [weak window] in
                guard let window, window.isVisible, !window.isKeyWindow else { return }
                window.makeKey()
            }
        }
    }
}

struct PickerRow: View {
    let title: String
    var subtitle: String?
    let selected: Bool
    var symbol: String?
    var icon: NSImage?
    var onHover: ((Bool) -> Void)?
    let action: () -> Void
    @State private var id = UUID()

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else if let symbol {
                        Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glideHover(id, cornerRadius: 8, opacity: 0.1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { onHover?($0) }
    }
}

struct BarWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            AppModel.captureBarWindow = window
            AppModel.shared.prewarmMainWindow()
            if AppModel.shared.launchedWithProject {
                window.alphaValue = 0
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { window.alphaValue = 1 }
            }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.level = .floating
            window.isMovableByWindowBackground = true
            window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary])
            window.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
