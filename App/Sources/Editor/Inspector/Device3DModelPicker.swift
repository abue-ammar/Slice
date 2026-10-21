//
//  Device3DModelPicker.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import SliceCore
import SwiftUI

struct ModelPicker: View {
    @ObservedObject var editor: EditorModel

    private var s: Device3DSettings { editor.project.device3D }

    var body: some View {
        let kinds = editor.available3DKinds
        VStack(alignment: .leading, spacing: 12) {
            ForEach(kinds, id: \.self) { kind in
                if kinds.count > 1 {
                    Text(kind.label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                }
                models(Device3DModel.models(kind))
            }
            finishes
        }
    }

    private func models(_ list: [Device3DModel]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(list, id: \.self) { model in
                    let finish = model == s.model ? s.finish : model.finishes[0]
                    PickerTile(selected: model == s.model, action: {
                        withAnimation(Theme.swap) { editor.select3DModel(model) }
                    }) {
                        VStack(spacing: 6) {
                            Device3DThumbnail(model: model, finish: finish,
                                              placement: model.kind == .laptop ? Device3DPlacement(yaw: -20, pitch: -14)
                                                  : Device3DPlacement(yaw: 24, pitch: 6),
                                              size: CGSize(width: 64, height: 76))
                            Text(model.shortLabel)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .foregroundStyle(model == s.model ? Color.primary : Color.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
    }

    private var finishes: some View {
            HStack(spacing: 8) {
                ForEach(s.model.finishes, id: \.self) { finish in
                    FinishSwatch(finish: finish, selected: s.finish == finish) {
                        withAnimation(.smooth(duration: 0.25)) { editor.project.device3D.finish = finish }
                    }
                }
                Spacer(minLength: 4)
                Text(s.finish.label)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
            }
            .animation(.smooth(duration: 0.25), value: s.finish)
    }
}

/// A rounded tile that lights up with Slice blue when chosen.
struct PickerTile<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            content
                .frame(maxWidth: .infinity)
                .background(shape.fill(selected ? Theme.accent.opacity(0.12) : hovering ? Theme.controlHover : Theme.control))
                .overlay(shape.strokeBorder(selected ? Theme.accent.opacity(0.9) : Color.white.opacity(hovering ? 0.1 : 0.04),
                                            lineWidth: selected ? 1.5 : 1))
                .contentShape(shape)
        }
        .buttonStyle(TilePressStyle())
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .animation(Theme.hover, value: selected)
    }
}

private struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

private struct FinishSwatch: View {
    let finish: Device3DFinish
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let c = finish.swatch
        Button(action: action) {
            Circle()
                .fill(Color(.sRGB, red: c.r, green: c.g, blue: c.b))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                .frame(width: 18, height: 18)
                .padding(3)
                .overlay(Circle().strokeBorder(selected ? Theme.accent : Color.white.opacity(hovering ? 0.25 : 0), lineWidth: 1.5))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(finish.label)
        .onHover { hovering = $0 }
        .animation(.smooth(duration: 0.2), value: selected)
        .animation(.smooth(duration: 0.15), value: hovering)
    }
}
