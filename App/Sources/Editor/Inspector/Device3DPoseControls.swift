//
//  Device3DPoseControls.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import SliceCore
import SwiftUI

/// One-click poses, drawn with the chosen device. They change the selected keyframe (or the one at the playhead)
/// when the phone is keyframed, and keep its place and size.
struct PosePresets: View {
    @ObservedObject var editor: EditorModel
    /// Keyframed, the pose changes along the timeline: follow the playhead.
    @ObservedObject private var clock: PlaybackClock

    init(editor: EditorModel) {
        self.editor = editor
        clock = editor.clock
    }

    static func presets(_ kind: Device3DKind) -> [(name: String, placement: Device3DPlacement)] {
        kind == .laptop ? laptopPresets : phonePresets
    }

    static let laptopPresets: [(name: String, placement: Device3DPlacement)] = [
        ("Front", Device3DPlacement(yaw: 0, pitch: -12)),
        ("Turned", Device3DPlacement(yaw: -16, pitch: -14)),
        ("Hero", Device3DPlacement(yaw: 28, pitch: -20)),
        ("Side", Device3DPlacement(yaw: 70, pitch: -6)),
        ("From above", Device3DPlacement(yaw: 0, pitch: -46)),
        ("Low", Device3DPlacement(yaw: -14, pitch: 4)),
    ]

    static let phonePresets: [(name: String, placement: Device3DPlacement)] = [
        ("Front", Device3DPlacement(yaw: 0, pitch: 0)),
        ("Turned", Device3DPlacement(yaw: 24, pitch: 4)),
        ("Hero", Device3DPlacement(yaw: -24, pitch: 12, rotation: 6)),
        ("Side", Device3DPlacement(yaw: 68, pitch: 2)),
        ("Lean back", Device3DPlacement(yaw: 0, pitch: 38)),
        ("Flat lay", Device3DPlacement(yaw: -10, pitch: 62, rotation: -16)),
    ]

    var body: some View {
        let s = editor.project.device3D
        let current = editor.editedPlacement
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(Self.presets(s.model.kind), id: \.name) { preset in
                let on = abs(current.yaw - preset.placement.yaw) < 0.5 && abs(current.pitch - preset.placement.pitch) < 0.5
                    && abs(current.rotation - preset.placement.rotation) < 0.5
                PickerTile(selected: on, action: {
                    withAnimation(Theme.move) {
                        editor.updatePlacement {
                            $0.yaw = preset.placement.yaw
                            $0.pitch = preset.placement.pitch
                            $0.rotation = preset.placement.rotation
                        }
                    }
                }) {
                    VStack(spacing: 2) {
                        Device3DThumbnail(model: s.model, finish: s.finish, placement: preset.placement, size: CGSize(width: 64, height: 64))
                        Text(preset.name)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(on ? Color.primary : Color.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }
}

/// A laptop's lid: how far it stands open (keyed along with the rest of the pose), and opening or closing it in one
/// click.
struct LidControl: View {
    @ObservedObject var editor: EditorModel
    /// Keyframed, the lid moves along the timeline: follow the playhead.
    @ObservedObject private var clock: PlaybackClock
    /// Offers the one-click moves (a keyframe's own controls leave them out).
    let animates: Bool

    init(editor: EditorModel, animates: Bool = true) {
        self.editor = editor
        self.animates = animates
        clock = editor.clock
    }

    var body: some View {
        PanelSlider("Lid", value: Binding(get: { editor.editedPlacement.lid }, set: { v in editor.updatePlacement { $0.lid = v } }),
                    in: Device3DSettings.lidRange, default: Device3DPlacement.openLid) { $0 < 0.5 ? "Closed" : "\(Int($0.rounded()))°" }
            .help("How far the lid stands open, from closed to leaning back")
        if animates {
            HStack(spacing: 8) {
                Text("Animate the lid").font(.system(size: 13))
                Spacer()
                Button("Open") { withAnimation(Theme.hover) { editor.animateLid(open: true) } }
                    .help("Keys the lid opening from the playhead, over \(String(format: "%.1f", EditorModel.lidMove)) seconds")
                Button("Close") { withAnimation(Theme.hover) { editor.animateLid(open: false) } }
                    .help("Keys the lid closing from the playhead, over \(String(format: "%.1f", EditorModel.lidMove)) seconds")
            }
            .buttonStyle(PillButtonStyle())
        }
    }
}

/// Whether the phone is animated by keyframes, and the way to start or add to them.
struct KeyframeBar: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let keys = editor.project.device3D.keyframes
        HStack(spacing: 10) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(keys.isEmpty ? Color.secondary : Theme.phone)
            Text(summary(keys))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            Spacer(minLength: 4)
            Button(keys.isEmpty ? "Animate" : "Add") {
                withAnimation(Theme.hover) { editor.addKeyframe(at: editor.time) }
            }
            .buttonStyle(PillButtonStyle())
            .help("Add a keyframe at the playhead, with the device's pose there")
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
        .animation(Theme.swap, value: keys.count)
    }

    private func summary(_ keys: [Device3DKeyframe]) -> String {
        switch keys.count {
        case 0: "Holds this pose. Add keyframes to move the device over time."
        case 1: "1 keyframe. Add another and the device moves between them."
        default: "\(keys.count) keyframes on the 3D track. Posing the device keys it at the playhead."
        }
    }
}

/// The fine pose controls, for the selected keyframe, the keyframe at the playhead, or the phone's one pose.
struct Device3DPoseSliders: View {
    @ObservedObject var editor: EditorModel
    /// Keyframed, the pose changes along the timeline: follow the playhead.
    @ObservedObject private var clock: PlaybackClock

    init(editor: EditorModel) {
        self.editor = editor
        clock = editor.clock
    }

    var body: some View {
        let p = editor.editedPlacement
        let d = Device3DPlacement.standard
        Group {
            PanelSlider("Turn", value: bind(\.yaw), in: -180 ... 180, default: d.yaw) { "\(Int($0.rounded()))°" }
                .help("Turns the device left or right, all the way round")
            PanelSlider("Tilt", value: bind(\.pitch), in: -180 ... 180, default: d.pitch) { "\(Int($0.rounded()))°" }
                .help("Tips the device's top away from you or towards you, all the way over")
            PanelSlider("Rotate", value: bind(\.rotation), in: -180 ... 180, default: 0) { "\(Int($0.rounded()))°" }
                .help("Spins the device in the picture, counter-clockwise")
            PanelSlider("Size", value: bind(\.scale), in: Device3DSettings.scaleRange, default: 1) { "\(Int(($0 * 100).rounded()))%" }
            PanelSlider("Left and right", value: Binding(get: { Double(p.position.x) }, set: { v in editor.updatePlacement { $0.position.x = v } }),
                        in: Device3DSettings.positionRange, default: 0) { offset($0) }
            PanelSlider("Up and down", value: Binding(get: { Double(p.position.y) }, set: { v in editor.updatePlacement { $0.position.y = v } }),
                        in: Device3DSettings.positionRange, default: 0) { offset($0) }
            PanelSlider("Perspective", value: Binding(get: { editor.project.device3D.perspective },
                                                      set: { editor.project.device3D.perspective = $0 }),
                        in: 0 ... 1, default: Device3DSettings().perspective) { $0 < 0.05 ? "Flat" : percent($0, of: 0 ... 1) }
                .help("Low is a long lens, nearly flat; high is a wide one, with strong depth")
        }
    }

    private func bind(_ keyPath: WritableKeyPath<Device3DPlacement, Double>) -> Binding<Double> {
        Binding(get: { editor.editedPlacement[keyPath: keyPath] }, set: { v in editor.updatePlacement { $0[keyPath: keyPath] = v } })
    }

    private func offset(_ v: Double) -> String { abs(v) < 0.005 ? "Centre" : String(format: "%+d%%", Int((v * 100).rounded())) }
}

/// The selected keyframe: its pose, how the phone moves into it, and removing it.
struct KeyframeInspector: View {
    @ObservedObject var editor: EditorModel
    let key: Device3DKeyframe

    private var previous: Device3DKeyframe? {
        editor.project.device3D.keyframes.filter { $0.time < key.time - 1e-6 }.max { $0.time < $1.time }
    }

    /// How long the move into this keyframe lasts, which the curve's preview plays at.
    private var lead: Double { previous.map { max(key.time - $0.time, 0.1) } ?? 1 }

    var body: some View {
        InfoRow(title: "Time", value: CutPin.label(key.time, precise: true))
        PanelSection("Pose") {
            PosePresets(editor: editor)
            if editor.project.device3D.model.kind == .laptop { LidControl(editor: editor, animates: false) }
            MoreOptions("Adjust", id: "device3D.keyframe.adjust", pinned: true) {
                Device3DPoseSliders(editor: editor)
            }
        }
        PanelDivider()
        PanelSection("Move into it") {
            MotionPicker(easing: Binding(get: { key.easing }, set: { e in editor.updateKeyframe(key.id) { $0.easing = e } }),
                         curve: Binding(get: { key.curve }, set: { c in editor.updateKeyframe(key.id) { $0.curve = c } }),
                         duration: lead, id: "device3D.keyframeMotion")
            PanelNote(previous == nil
                ? "This is the first keyframe: the device holds its pose until here."
                : "How the device moves from the keyframe before to this one, over \(String(format: "%.1fs", lead)).")
        }
        Button("Delete keyframe") { editor.deleteSelection() }
            .buttonStyle(DestructiveButtonStyle())
    }
}
