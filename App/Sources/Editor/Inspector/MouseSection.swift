//
//  MouseSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/9/26.
//

import SliceCore
import SwiftUI

struct MouseSection: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let clips = editor.project.clips
        let editable = clips.contains(where: \.hasEditableCursor)
        let inVideo = clips.contains { $0.cursorFile != nil && $0.cursorInVideo }
        let cursor = editor.project.cursor
        let d = CursorSettings()
        PanelSection("Cursor", trailing: AnyView(
            Toggle("Show cursor", isOn: $editor.project.cursor.visible.animation(.snappy))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.accent)
                .disabled(!editable)
                .help("Show cursor"))) {
            Group {
                if cursor.visible {
                    CursorStylePicker(selection: $editor.project.cursor.style)
                    PanelSlider("Size", value: $editor.project.cursor.size, in: 0.5 ... 6, default: d.size) {
                        String(format: "%.1f×", $0)
                    }
                    IdleCursorControls(cursor: $editor.project.cursor)
                }
            }
            .disabled(!editable)
            if !editable && inVideo {
                PanelNote("These takes have the cursor recorded into the video, so it can't be changed. Takes recorded from now on can.")
            } else if !editable {
                PanelNote("No mouse movement was recorded for these clips.")
            } else if inVideo {
                PanelNote("Older takes keep the cursor recorded into their video.")
            }
        }
        if cursor.visible && editable {
            PanelDivider()
            PanelSection("Movement") {
                PanelSlider("Smoothness", value: $editor.project.cursor.smoothing, in: 0 ... 1, default: d.smoothing) {
                    $0 < 0.01 ? "Raw" : "\(Int(($0 * 100).rounded()))%"
                }
                .help("Removes hand jitter from the recorded path. It looks ahead as well as back, so it never lags.")
                PanelSlider("Motion blur", value: $editor.project.cursor.motionBlur, in: 0 ... 1, default: d.motionBlur) {
                    blurLabel($0)
                }
                .help("Blurs the pointer along its path while it moves fast; a still pointer stays sharp.")
                PanelSlider("Tilt", value: $editor.project.cursor.tilt, in: 0 ... 1, default: d.tilt) {
                    $0 < 0.01 ? "Off" : "\(Int(($0 * 100).rounded()))%"
                }
                .help("Leans the pointer gently into sideways movement, upright again when it stops.")
                MoreOptions(id: "cursorMovement") {
                    if cursor.tilt >= 0.01 {
                        PanelSlider("Maximum tilt", value: $editor.project.cursor.tiltMaxAngle, in: 4 ... 30, default: d.tiltMaxAngle) {
                            "\(Int($0.rounded()))°"
                        }
                        PanelSlider("Tilt response", value: $editor.project.cursor.tiltSmoothing, in: 0.05 ... 0.5,
                                    default: d.tiltSmoothing) { String(format: "%.2fs", $0) }
                            .help("How much movement the lean follows. Longer is calmer.")
                    }
                    PanelToggle("Return to the start at the end", isOn: $editor.project.cursor.loopPosition)
                    PanelNote("The pointer glides back to where it began, for videos that loop.")
                    if cursor.style.followsSystemCursor {
                        PanelSlider("Ignore quick cursor changes", value: $editor.project.cursor.stateDelay, in: 0 ... 0.4,
                                    default: d.stateDelay) { $0 < 0.005 ? "Off" : "\(Int(($0 * 1000).rounded())) ms" }
                        PanelNote("The pointer turns into a hand over links and an I-beam over text. Changes shorter than this are skipped, so passing over things doesn't flicker.")
                    }
                }
            }
        }
        PanelDivider()
        ClicksSection(editor: editor, pointerShown: cursor.visible && editable)
        .animation(.snappy, value: cursor.visible)
        .animation(Theme.swap, value: cursor.hideWhenIdle)
        .animation(.snappy, value: cursor.tilt >= 0.01)
    }

    private func blurLabel(_ v: Double) -> String {
        switch v {
        case ..<0.01: "Off"
        case ..<0.3: "Subtle"
        case ..<0.6: "Medium"
        default: "Strong"
        }
    }
}

private struct IdleCursorControls: View {
    @Binding var cursor: CursorSettings
    @State private var custom = false

    private static let customTag = -1.0

    var body: some View {
        let presets = CursorSettings.idleDelayPresets
        let isPreset = presets.contains { abs($0 - cursor.idleDelay) < 0.001 }
        PanelToggle("Hide when idle", isOn: $cursor.hideWhenIdle)
            .help("Fades the pointer out once it rests; it's back the moment the mouse moves or clicks")
        if cursor.hideWhenIdle {
            SegmentedControl(selection: Binding(
                get: { custom || !isPreset ? Self.customTag : cursor.idleDelay },
                set: { v in
                    custom = v == Self.customTag
                    if !custom { cursor.idleDelay = v }
                }),
                options: presets + [Self.customTag],
                title: { $0 == Self.customTag ? "Custom" : String(format: $0 < 1 ? "%.1fs" : "%.0fs", $0) })
                .transition(.opacity.combined(with: .move(edge: .top)))
            if custom || !isPreset {
                PanelSlider("Hide after", value: $cursor.idleDelay, in: 0.2 ... 15) { String(format: $0 < 10 ? "%.1fs" : "%.0fs", $0) }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct CursorStylePicker: View {
    @Binding var selection: CursorStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(CursorStyle.Family.allCases, id: \.self) { family in
                VStack(alignment: .leading, spacing: 6) {
                    Text(family.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(CursorStyle.allCases.filter { $0.family == family }, id: \.self) { style in
                            CursorStyleTile(style: style, selected: selection == style) {
                                withAnimation(Theme.hover) { selection = style }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct CursorStyleTile: View {
    let style: CursorStyle
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    ForEach(style.previewTypes, id: \.self) { type in
                        if let image = CursorPreviewImages.image(style, type) { Image(nsImage: image) }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                Text(style.label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(selected || hovering ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 4)
            .padding(.top, 9)
            .padding(.bottom, 7)
            .background(shape.fill(selected ? Theme.accent.opacity(0.1) : hovering ? Theme.controlHover : Theme.control))
            .overlay(shape.strokeBorder(Theme.accent.opacity(selected ? 0.9 : 0), lineWidth: 1.5))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .animation(Theme.hover, value: selected)
        .help(help)
    }

    private var help: String {
        switch style.family {
        case .macOS: "\(style.label) cursors: changes with the system cursor (hand over links, I-beam over text...)"
        case .cute: style.previewTypes.count > 1
            ? "\(style.label): turns into its hand over links" : "Always draws the \(style.label.lowercased()) pointer"
        case .simple: "Always draws this \(style.label.lowercased()) pointer"
        }
    }
}

@MainActor
private enum CursorPreviewImages {
    private static var cache: [String: NSImage] = [:]
    private static let size: CGFloat = 1.1

    static func image(_ style: CursorStyle, _ type: CursorType) -> NSImage? {
        let key = "\(style.rawValue)|\(type.rawValue)"
        if let cached = cache[key] { return cached }
        guard let (cg, _) = style.preview(type, scale: size * 2) else { return nil }
        let image = NSImage(cgImage: cg, size: CGSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        cache[key] = image
        return image
    }
}
