//
//  KeystrokesSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/11/26.
//

import AVFoundation
import SliceCore
import SwiftUI

struct KeystrokesSection: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let keys = editor.project.keystrokes
        let d = KeystrokeSettings()
        let subs = editor.project.subtitles
        PanelSection("Shortcuts") {
            KeystrokePreview(visible: keys.visible, position: keys.position,
                             captions: subs.burnIn && !editor.captions.isEmpty && subs.position.rawValue == keys.position.rawValue)
            PanelToggle("Show shortcuts", isOn: $editor.project.keystrokes.visible)
            if !editor.hasKeystrokes {
                PanelNote("None were recorded in these takes. Turn on Record keyboard before recording (it needs Accessibility access).")
            }
        }
        if keys.visible {
            PanelDivider()
            PanelSection("Keys") {
                PanelToggle("Include single keys", isOn: $editor.project.keystrokes.singleKeys)
                PanelNote("Esc, return, tab, delete, arrows and function keys on their own. Plain typing is never recorded.")
            }
            PanelDivider()
            PanelSection("Appearance") {
                SegmentedControl(selection: $editor.project.keystrokes.position, options: [.bottom, .top],
                                 title: { $0 == .bottom ? "Bottom" : "Top" })
                PanelSlider("Size", value: $editor.project.keystrokes.size, in: 0.02 ... 0.08, default: d.size) {
                    String(format: "%.1f×", $0 / d.size)
                }
                PanelSlider("Duration", value: $editor.project.keystrokes.hold, in: 0.5 ... 4, default: d.hold) {
                    String(format: "%.1fs", $0)
                }
                .help("How long a shortcut stays after it's pressed. Pressing it again keeps it up and counts it.")
            }
        }
        PanelDivider()
        PanelSection("Typing sound") {
            SoundPicker(selection: $editor.project.keystrokes.sound, options: KeyboardSound.allCases,
                        label: \.label, detail: \.detail) { sound in
                KeyboardSoundPreview.play(sound, volume: editor.project.keystrokes.soundVolume)
            }
            if keys.sound != .none {
                SoundVolumeRow(value: $editor.project.keystrokes.soundVolume, default: d.soundVolume, icon: "keyboard")
                    .transition(.opacity.combined(with: .move(edge: .top)))
                Button {
                    KeyboardSoundPreview.play(keys.sound, volume: keys.soundVolume)
                } label: {
                    Label("Play typing preview", systemImage: "speaker.wave.2")
                }
                .buttonStyle(PillButtonStyle(fullWidth: true))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !editor.hasKeyHits {
                PanelNote("No typing was recorded in these takes. Turn on Record keyboard before recording (it needs Accessibility access).")
            }
        }
        .animation(Theme.swap, value: keys.sound == .none)
    }
}

@MainActor
enum KeyboardSoundPreview {
    private static var players: [AVAudioPlayer] = []

    private static let phrase: [(gap: Double, kind: KeyHit.Kind)] = [
        (0, .modifier), (0.07, .key), (0.12, .key), (0.1, .key), (0.11, .key), (0.13, .key), (0.15, .space),
        (0.13, .key), (0.1, .key), (0.11, .key), (0.1, .key), (0.12, .key), (0.24, .enter),
    ]

    static func play(_ sound: KeyboardSound, volume: Double) {
        players.forEach { $0.stop() }
        players = []
        let files = sound.files
        let picks = sound.picks(for: phrase.map(\.kind))
        guard !picks.isEmpty else { return }
        var times: [Double] = []
        var at = 0.05
        for (step, pick) in zip(phrase, picks) {
            at += step.gap
            guard let player = try? AVAudioPlayer(contentsOf: files[pick]) else { continue }
            player.volume = Float(min(max(volume, 0), 1))
            player.prepareToPlay()
            players.append(player)
            times.append(at)
        }
        guard let now = players.first?.deviceCurrentTime else { return }
        for (player, t) in zip(players, times) { player.play(atTime: now + t) }
    }
}

private struct KeystrokePreview: View {
    let visible: Bool
    let position: KeystrokeSettings.Position
    let captions: Bool
    @State private var index = 0

    private static let combos = [["⌘", "K"], ["⇧", "⌘", "P"], ["⌘", "Z"], ["⌥", "⌘", "←"]]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack(alignment: position == .bottom ? .bottom : .top) {
            shape.fill(Color.white.opacity(0.025))
            VStack(alignment: .leading, spacing: 7) {
                Capsule().frame(width: 92, height: 5)
                Capsule().frame(width: 140, height: 5)
                Capsule().frame(width: 64, height: 5)
            }
            .foregroundStyle(Color.white.opacity(0.05))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 18)
            if visible || captions {
                VStack(spacing: 7) {
                    if captions && position == .top { caption }
                    ZStack {
                        if visible {
                            HStack(spacing: 4) {
                                ForEach(Array(Self.combos[index % Self.combos.count].enumerated()), id: \.offset) { _, key in
                                    Keycap(label: key)
                                }
                            }
                            .id(index)
                            .transition(.keycap)
                        }
                    }
                    if captions && position == .bottom { caption }
                }
                .padding(.vertical, captions ? 11 : 14)
            }
        }
        .frame(height: 112)
        .overlay(shape.strokeBorder(Theme.stroke))
        .animation(Theme.slide, value: position)
        .animation(Theme.slide, value: captions)
        .task(id: visible) {
            while visible && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                index += 1
            }
        }
    }
}

extension KeystrokePreview {
    private var caption: some View {
        HStack(spacing: 5) {
            ForEach([26, 18, 34, 22], id: \.self) { w in
                Capsule().fill(Color.white.opacity(0.45)).frame(width: CGFloat(w), height: 5)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color(white: 0.09)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .transition(.opacity)
    }
}

private struct Keycap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 7)
            .frame(minWidth: 26, minHeight: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color(white: 0.15)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .white.opacity(0.03)],
                                             startPoint: .top, endPoint: .bottom)))
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1.5)
    }
}

private struct KeycapFocus: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat
    let drop: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: blur).scaleEffect(scale).offset(y: drop).opacity(opacity)
    }
}

private extension AnyTransition {
    static var keycap: AnyTransition {
        let sharp = KeycapFocus(blur: 0, opacity: 1, scale: 1, drop: 0)
        return .asymmetric(
            insertion: .modifier(active: KeycapFocus(blur: 8, opacity: 0, scale: 0.92, drop: 6), identity: sharp)
                .animation(.timingCurve(0.215, 0.61, 0.355, 1, duration: 0.32).delay(0.05)),
            removal: .modifier(active: KeycapFocus(blur: 8, opacity: 0, scale: 0.95, drop: 0), identity: sharp)
                .animation(.easeIn(duration: 0.12)))
    }
}
