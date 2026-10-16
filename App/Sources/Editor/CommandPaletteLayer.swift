//
//  CommandPaletteLayer.swift
//  Slice
//
//  Created by rit3zh CX on 10/2/26.
//

import AppKit
import SwiftUI

struct CommandPaletteLayer: View {
    let isPresented: Bool
    let commands: [EditorCommand]
    let close: () -> Void
    let run: (EditorCommand) -> Void

    static let showAnimation = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.32)
    static let hideAnimation = Animation.timingCurve(0.4, 0, 1, 1, duration: 0.14)
    static let hideDuration = 0.14

    var body: some View {
        ZStack(alignment: .top) {
            if isPresented {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture(perform: close)
                    .transition(.opacity)
                CommandPalette(commands: commands, close: close, run: run)
                    .geometryGroup()
                    .padding(.top, 64)
                    .transition(.palette)
            }
        }
        .animation(isPresented ? Self.showAnimation : Self.hideAnimation, value: isPresented)
    }
}

private struct PaletteFocus: ViewModifier {
    let t: CGFloat
    let scale: CGFloat
    let rise: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - scale * t, anchor: .top)
            .offset(y: -rise * t)
            .opacity(1 - t)
    }
}

private extension AnyTransition {
    static var palette: AnyTransition {
        .asymmetric(
            insertion: .modifier(active: PaletteFocus(t: 1, scale: 0.04, rise: 10), identity: PaletteFocus(t: 0, scale: 0.04, rise: 10)),
            removal: .modifier(active: PaletteFocus(t: 1, scale: 0.02, rise: 4), identity: PaletteFocus(t: 0, scale: 0.02, rise: 4)))
    }
}

// MARK: - Shortcut toast

struct ShortcutToast: View {
    let title: String
    let keys: [String]
    @State private var down = -1
    @State private var released = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(Array(keys.enumerated()), id: \.offset) { i, key in
                    KeyCap(key: key, pressed: i <= down && !released, large: true)
                }
            }
            Text(title).font(.system(size: 13, weight: .medium))
        }
        .padding(.leading, 8)
        .padding(.trailing, 16)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color(white: 0.11)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.1)))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 8)
        .task {
            try? await Task.sleep(for: .milliseconds(180))
            for i in keys.indices {
                withAnimation(.snappy(duration: 0.12)) { down = i }
                try? await Task.sleep(for: .milliseconds(90))
            }
            try? await Task.sleep(for: .milliseconds(240))
            withAnimation(.snappy(duration: 0.18)) { released = true }
        }
    }
}

extension AnyTransition {
    static var toast: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: 16))
    }
}
