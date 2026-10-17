//
//  ClicksSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/7/26.
//

import AVFoundation
import SliceCore
import SwiftUI

struct ClicksSection: View {
    @ObservedObject var editor: EditorModel
    let pointerShown: Bool

    var body: some View {
        let cursor = editor.project.cursor
        let d = CursorSettings()
        PanelSection("Click sound") {
            SoundPicker(selection: $editor.project.cursor.clickSound, options: ClickSound.allCases,
                        label: \.label, detail: \.detail) { sound in
                ClickSoundPreview.play(sound, volume: editor.project.cursor.clickSoundVolume)
            }
            if cursor.clickSound != .none {
                SoundVolumeRow(value: $editor.project.cursor.clickSoundVolume, default: d.clickSoundVolume, icon: "computermouse")
                    .transition(.opacity.combined(with: .move(edge: .top)))
                Button {
                    ClickSoundPreview.play(cursor.clickSound, volume: cursor.clickSoundVolume)
                } label: {
                    Label("Play click sound preview", systemImage: "speaker.wave.2")
                }
                .buttonStyle(PillButtonStyle(fullWidth: true))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if !editor.hasClicks { PanelNote("No clicks were recorded in these takes.") }
        }
        .animation(Theme.swap, value: cursor.clickSound == .none)
        PanelDivider()
        PanelSection("Click effect") {
            SegmentedControl(selection: $editor.project.cursor.clickEffect, options: ClickEffect.allCases, title: \.label)
            if cursor.clickEffect != .none {
                PanelSlider("Size", value: $editor.project.cursor.clickEffectSize, in: 0.5 ... 2.5, default: 1) {
                    String(format: "%.1f×", $0)
                }
            }
            if pointerShown {
                PanelToggle("Press cursor on click", isOn: $editor.project.cursor.clickPress)
                    .help("The pointer dips in size at each click, then eases back.")
                if cursor.clickPress {
                    HStack(spacing: 14) {
                        ClickPressPreview(settings: cursor)
                        VStack(spacing: 12) {
                            PanelSlider("Size", value: $editor.project.cursor.clickPressScale, in: 0.5 ... 1.5,
                                        default: d.clickPressScale) { "\(Int(($0 * 100).rounded()))%" }
                                .help("Below 100% the pointer shrinks as it clicks; above, it grows.")
                            PanelSlider("Length", value: $editor.project.cursor.clickPressDuration, in: 0.1 ... 0.8,
                                        default: d.clickPressDuration) { String(format: "%.2fs", $0) }
                                .help("How long the press takes, from the click until the pointer is back to size.")
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .animation(.snappy, value: cursor.clickEffect)
        .animation(Theme.swap, value: cursor.clickPress)
        PanelDivider()
        SpotlightControls(spotlight: $editor.project.cursor.spotlight)
    }
}

private struct SpotlightControls: View {
    @Binding var spotlight: ClickSpotlight

    var body: some View {
        let d = ClickSpotlight()
        PanelSection("Spotlight") {
            PanelToggle("Spotlight each click", isOn: $spotlight.enabled)
                .help("A soft circle of focus around each click, while the rest of the screen dims or blurs for a moment.")
            if !spotlight.enabled {
                PanelNote("Or place one yourself on the timeline's Spotlight track, on a spot or following the pointer.")
                    .transition(.opacity)
            }
            if spotlight.enabled {
                VStack(spacing: 12) {
                    SegmentedControl(selection: $spotlight.mode, options: SpotlightMode.allCases, title: \.label,
                                     symbol: { $0.symbol })
                    PanelSlider("Size", value: $spotlight.size, in: 0.5 ... 2.5, default: d.size) {
                        String(format: "%.1f×", $0)
                    }
                    PanelSlider(spotlight.mode == .dim ? "Dim" : "Blur", value: $spotlight.strength, in: 0.1 ... 1,
                                default: d.strength) { "\(Int(($0 * 100).rounded()))%" }
                    MoreOptions(id: "clickSpotlight") {
                        PanelSlider("Hold", value: $spotlight.hold, in: 0.3 ... 3, default: d.hold) {
                            String(format: "%.1fs", $0)
                        }
                        .help("How long the spotlight stays after each click before it fades.")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(Theme.swap, value: spotlight.enabled)
    }
}

struct SoundPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let label: (Option) -> String
    let detail: (Option) -> String
    let picked: (Option) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(options, id: \.self) { option in
                SoundCard(label: label(option), detail: detail(option), selected: option == selection) {
                    withAnimation(Theme.hover) { selection = option }
                    picked(option)
                }
            }
        }
    }
}

private struct SoundCard: View {
    let label: String
    let detail: String
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(selected || hovering ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(shape.fill(selected ? Theme.thumb : hovering ? Theme.controlHover : Theme.control))
            .overlay(shape.strokeBorder(Color.white.opacity(selected ? 0.2 : 0), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .animation(Theme.hover, value: selected)
    }
}

struct SoundVolumeRow: View {
    @Binding var value: Double
    let defaultValue: Double
    let icon: String

    init(value: Binding<Double>, default defaultValue: Double, icon: String) {
        _value = value
        self.defaultValue = defaultValue
        self.icon = icon
    }

    var body: some View {
        let changed = abs(value - defaultValue) > 0.0001
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Volume").font(.system(size: 13))
                Spacer()
                Text(value > 0 ? "\(Int((value * 100).rounded()))%" : "Muted")
                    .font(.rounded(12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy(duration: 0.25), value: Int((value * 100).rounded()))
            }
            HStack(spacing: 10) {
                SmoothSlider(value: $value, in: 0 ... 1)
                Button("Reset") { withAnimation(Theme.slide) { value = defaultValue } }
                    .buttonStyle(PillButtonStyle())
                    .disabled(!changed)
            }
        }
    }
}

private struct ClickPressPreview: View {
    let settings: CursorSettings
    @State private var start = Date()
    @Environment(\.displayScale) private var displayScale

    private static let size: CGFloat = 1.8
    private static let side: CGFloat = 76
    private static let ring = 0.45

    var body: some View {
        let type = settings.style.previewTypes.last ?? .arrow
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        ZStack {
            shape.fill(Color.white.opacity(0.03))
            if let (cg, hotspot) = settings.style.preview(type, scale: Self.size * displayScale) {
                let w = CGFloat(cg.width) / displayScale, h = CGFloat(cg.height) / displayScale
                let anchor = UnitPoint(x: hotspot.x / CGFloat(cg.width), y: hotspot.y / CGFloat(cg.height))
                let hot = CGSize(width: (anchor.x - 0.5) * w, height: (anchor.y - 0.5) * h)
                let period = max(settings.clickPressDuration, Self.ring) + 0.8
                SwiftUI.TimelineView(.animation) { context in
                    let age = context.date.timeIntervalSince(start).truncatingRemainder(dividingBy: period)
                    let p = min(age / Self.ring, 1)
                    let open = 1 - pow(1 - p, 3)
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.3 * (1 - p)), lineWidth: 1)
                            .frame(width: 6 + 24 * open, height: 6 + 24 * open)
                            .offset(hot)
                        Image(decorative: cg, scale: displayScale)
                            .scaleEffect(settings.pressScale(ages: [age]), anchor: anchor)
                    }
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .overlay(shape.strokeBorder(Theme.stroke))
        .accessibilityHidden(true)
    }
}

@MainActor
enum ClickSoundPreview {
    private static var players: [ClickSound: AVAudioPlayer] = [:]

    static func play(_ sound: ClickSound, volume: Double) {
        guard let url = sound.url else { return }
        guard let player = players[sound] ?? (try? AVAudioPlayer(contentsOf: url)) else { return }
        players[sound] = player
        player.volume = Float(min(max(volume, 0), 1))
        player.currentTime = 0
        player.play()
    }
}
