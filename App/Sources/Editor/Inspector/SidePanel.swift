//
//  SidePanel.swift
//  Slice
//
//  Created by rit3zh CX on 10/9/26.
//

import SliceCore
import SwiftUI

enum InspectorTab: String, CaseIterable {
    // Shortcuts number the tabs in this order (⌘1…), so new ones go last.
    case cursor, keyboard, frame, camera, audio, output, transcript, subtitles, device3D

    /// The rail's order: the 3D phone sits beside the flat frame.
    static let railOrder: [InspectorTab] = [.cursor, .keyboard, .frame, .device3D, .camera, .audio, .output, .transcript, .subtitles]

    /// The 3D tab is there once there's a take to show on a device (an iPhone take on a phone, a screen recording on a Mac).
    func isAvailable(in project: Project) -> Bool { self != .device3D || !project.clips.isEmpty }

    var title: String {
        switch self {
        case .cursor: "Cursor"
        case .keyboard: "Keyboard"
        case .frame: "Frame"
        case .camera: "Camera"
        case .audio: "Audio"
        case .output: "Output"
        case .transcript: "Transcript"
        case .subtitles: "Subtitles"
        case .device3D: "3D"
        }
    }

    var symbol: String {
        switch self {
        case .cursor: "cursorarrow.rays"
        case .keyboard: "keyboard"
        case .frame: "photo.artframe"
        case .camera: "person.crop.rectangle"
        case .audio: "speaker.wave.2"
        case .output: "slider.horizontal.3"
        case .transcript: "text.quote"
        case .subtitles: "captions.bubble"
        case .device3D: "cube"
        }
    }
}

struct SidePanel: View {
    @ObservedObject var editor: EditorModel
    @AppStorage("sidePanel.tab") private var tabRaw = InspectorTab.frame.rawValue
    @Namespace private var rail
    @State private var tooltip = RailTooltipState()

    private var tab: InspectorTab {
        let t = InspectorTab(rawValue: tabRaw) ?? .frame
        return t.isAvailable(in: editor.project) ? t : .frame
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                ForEach(InspectorTab.railOrder.filter { $0.isAvailable(in: editor.project) }, id: \.self) { t in
                    RailButton(symbol: t.symbol, selected: editor.selection == nil && t == tab, namespace: rail,
                               badge: t == .audio && !editor.project.music.isEmpty,
                               hover: { tooltip.hover(t, $0) }) {
                        withAnimation(Theme.slide) {
                            tabRaw = t.rawValue
                            editor.selection = nil
                        }
                    }
                    .anchorPreference(key: RailAnchors.self, value: .bounds) { [t: $0] }
                    .accessibilityLabel(t.title)
                }
            }
            .padding(.top, 2)
            .overlayPreferenceValue(RailAnchors.self) { anchors in
                GeometryReader { geo in
                    if let t = tooltip.tab, let anchor = anchors[t] {
                        RailTooltip(text: t.title, rect: geo[anchor], visible: tooltip.visible)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .zIndex(1)

            VStack(spacing: 0) {
                Group {
                    if editor.selection != nil {
                        SelectionInspector(editor: editor)
                    } else {
                        switch tab {
                        case .transcript: TranscriptView(editor: editor)
                        case .subtitles: SubtitlesEditorView(editor: editor)
                        default: InspectorView(editor: editor, tab: tab)
                        }
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(y: 6)),
                    removal: .opacity.animation(.easeOut(duration: 0.1))))
                .id(editor.selection == nil ? tab.rawValue : "selection")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.stroke))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .animation(Theme.swap, value: tab)
            .animation(Theme.swap, value: editor.selection)
        }
    }
}

private struct RailAnchors: PreferenceKey {
    static let defaultValue: [InspectorTab: Anchor<CGRect>] = [:]
    static func reduce(value: inout [InspectorTab: Anchor<CGRect>], nextValue: () -> [InspectorTab: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

@Observable
@MainActor
final class RailTooltipState {
    private(set) var tab: InspectorTab?
    private(set) var visible = false
    @ObservationIgnored private var hovering: InspectorTab?
    @ObservationIgnored private var pending: Task<Void, Never>?

    func hover(_ t: InspectorTab, _ inside: Bool) {
        if inside {
            hovering = t
            pending?.cancel()
            if visible {
                withAnimation(.smooth(duration: 0.32)) { tab = t }
            } else {
                tab = t
                pending = Task {
                    try? await Task.sleep(for: .milliseconds(380))
                    guard !Task.isCancelled else { return }
                    withAnimation(.smooth(duration: 0.2)) { visible = true }
                }
            }
        } else if hovering == t {
            hovering = nil
            pending?.cancel()
            pending = Task {
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.15)) { visible = false }
            }
        }
    }
}

private struct RailTooltip: View {
    let text: String
    let rect: CGRect
    let visible: Bool

    private static let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    private static let height: CGFloat = 24

    private var width: CGFloat {
        ceil((text as NSString).size(withAttributes: [.font: Self.font]).width) + 20
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        ZStack {
            Text(text)
                .font(Font(Self.font))
                .foregroundStyle(.primary)
                .fixedSize()
                .id(text)
                .transition(.tooltipText)
        }
        .frame(width: width, height: Self.height)
        .clipShape(shape)
        .background(shape.fill(Color(white: 0.17)))
        .overlay(shape.strokeBorder(Color.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
        .scaleEffect(visible ? 1 : 0.94, anchor: .trailing)
        .opacity(visible ? 1 : 0)
        .offset(x: rect.minX - 8 - width, y: rect.midY - Self.height / 2)
        .allowsHitTesting(false)
    }
}

private struct SoftFocus: ViewModifier {
    let amount: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: amount * 4).opacity(1 - amount).scaleEffect(1 - amount * 0.08)
    }
}

private extension AnyTransition {
    static var tooltipText: AnyTransition {
        .modifier(active: SoftFocus(amount: 1), identity: SoftFocus(amount: 0))
    }
}

private struct RailButton: View {
    let symbol: String
    let selected: Bool
    let namespace: Namespace.ID
    var badge = false
    let hover: (Bool) -> Void
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(selected ? Color.primary : hovering ? Color.primary.opacity(0.85) : Color.secondary)
                .frame(width: 34, height: 34)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Theme.music).frame(width: 5, height: 5).padding(6)
                        .opacity(badge ? 1 : 0).scaleEffect(badge ? 1 : 0.4)
                        .animation(Theme.swap, value: badge)
                }
                .background {
                    if selected {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Theme.thumb)
                            .matchedGeometryEffect(id: "rail", in: namespace)
                    } else if hovering {
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.control)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(RailPress())
        .onHover { inside in
            hovering = inside
            hover(inside)
        }
        .animation(Theme.hover, value: hovering)
    }
}

private struct RailPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}
