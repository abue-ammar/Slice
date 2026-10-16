//
//  ProjectsBarControls.swift
//  Slice
//
//  Created by rit3zh CX on 10/2/26.
//

import SliceCore
import SwiftUI

struct NewRecordingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(red: 0.95, green: 0.27, blue: 0.27))
                    .frame(width: 7, height: 7)
                Text("New Recording")
            }
        }
        .modifier(GlassOr(shape: Capsule(), pill: true))
    }
}

struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var hovering = false

    private var active: Bool { focused || !text.isEmpty }

    var body: some View {
        let shape = Capsule()
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active || hovering ? Color.secondary : Color.secondary.opacity(0.7))
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
                .onExitCommand {
                    text = ""
                    focused = false
                }
            ZStack {
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                } else if !focused {
                    Text("⌘F")
                        .font(.rounded(10.5, .medium))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Theme.stroke.opacity(1.6)))
                        .transition(.opacity)
                }
            }
        }
        .padding(.leading, 11)
        .padding(.trailing, 8)
        .frame(width: active ? 240 : 184, height: 30)
        .geometryGroup()
        .modifier(SearchSurface(shape: shape, active: active, hovering: hovering, focused: focused))
        .contentShape(shape)
        .onTapGesture { focused = true }
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .animation(.smooth(duration: 0.28), value: active)
        .animation(Theme.hover, value: text.isEmpty)
        .background {
            Button("") { focused = true }.keyboardShortcut("f", modifiers: .command).hidden()
        }
    }
}

// MARK: - Glass

/// On macOS 26, renders the bar's glass pieces together. They only merge when they touch: a blend distance as wide as
/// the gap between them left them on the edge of merging as the search field grew, flickering every frame.
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: 0) { content }
        } else {
            content
        }
    }
}

struct GlassOr<S: Shape>: ViewModifier {
    let shape: S
    let pill: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.buttonStyle(GlassBarButtonStyle(shape: shape))
        } else if pill {
            content.buttonStyle(PillButtonStyle())
        } else {
            content.buttonStyle(IconButtonStyle(size: 30, iconSize: 14))
        }
    }
}

@available(macOS 26, *)
private struct GlassBarButtonStyle<S: Shape>: ButtonStyle {
    let shape: S

    func makeBody(configuration: Configuration) -> some View {
        GlassBarButton(configuration: configuration, shape: shape)
    }
}

@available(macOS 26, *)
private struct GlassBarButton<S: Shape>: View {
    let configuration: ButtonStyleConfiguration
    let shape: S
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(hovering ? Color.primary : Color.primary.opacity(0.8))
            .padding(.horizontal, S.self == Circle.self ? 0 : 13)
            .frame(minWidth: 30, minHeight: 30)
            .contentShape(shape)
            .glassEffect(.regular.interactive(), in: shape)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 && isEnabled }
            .animation(Theme.hover, value: hovering)
    }
}

private struct SearchSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    let active: Bool
    let hovering: Bool
    let focused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content
                .background(shape.fill(Color.white.opacity(active ? 0.05 : 0)))
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(active ? Theme.controlHover : hovering ? Theme.control.opacity(1.4) : Theme.control))
                .overlay(shape.strokeBorder(Color.white.opacity(focused ? 0.1 : 0), lineWidth: 1))
        }
    }
}

struct EmptyProjects: View {
    let record: () -> Void
    let importVideos: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("No projects yet")
                .font(.rounded(15, .semibold))
            Text("Record your screen, or start from a video you already have.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(action: importVideos) { Text("Import Video…") }
                    .modifier(GlassOr(shape: Capsule(), pill: true))
                NewRecordingButton(action: record)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }
}
