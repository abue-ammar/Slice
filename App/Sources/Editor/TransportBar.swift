//
//  TransportBar.swift
//  Slice
//
//  Created by rit3zh CX on 10/9/26.
//

import SliceCore
import SwiftUI

struct TransportBar: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var clock: PlaybackClock
    @Binding var timelineZoom: Double

    init(editor: EditorModel, timelineZoom: Binding<Double>) {
        self.editor = editor
        clock = editor.clock
        _timelineZoom = timelineZoom
    }

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { editor.toggleCutting() } label: { Image(systemName: "scissors") }
                    .buttonStyle(IconButtonStyle(selected: editor.isCutting, size: 30, iconSize: 14))
                    .help(editor.isCutting ? "Stop cutting (Esc)" : "Cut tool: click a clip to split it there")
                Menu {
                    Picker("Playback speed", selection: $editor.playbackRate) {
                        ForEach([0.5, 1, 1.5, 2] as [Float], id: \.self) { r in
                            Text(r == 1 ? "Normal" : String(format: "%g×", r)).tag(r)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(String(format: "%g×", editor.playbackRate))
                        .font(.rounded(12).monospacedDigit())
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(PillButtonStyle(selected: editor.playbackRate != 1))
                .fixedSize()
                .help("Preview playback speed (doesn't affect the export)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 12) {
                timecode(clock.time)
                    .foregroundStyle(.primary)
                    .frame(width: 64, alignment: .trailing)
                Button { editor.seek(to: 0) } label: { Image(systemName: "backward.end.fill") }
                    .buttonStyle(IconButtonStyle(size: 32, iconSize: 14))
                    .help("Go to start")
                Button { editor.togglePlay() } label: { PlayPauseGlyph(playing: clock.isPlaying) }
                .buttonStyle(PlayButtonStyle())
                .help(clock.isPlaying ? "Pause (Space)" : "Play (Space)")
                Button { editor.seek(to: editor.duration) } label: { Image(systemName: "forward.end.fill") }
                    .buttonStyle(IconButtonStyle(size: 32, iconSize: 14))
                    .help("Go to end")
                timecode(editor.duration)
                    .foregroundStyle(.tertiary)
                    .frame(width: 64, alignment: .leading)
            }
            .fixedSize()

            HStack(spacing: 8) {
                Button { withAnimation(Theme.swap) { timelineZoom = max(timelineZoom / 1.5, 1) } } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(IconButtonStyle(size: 24, iconSize: 12))
                .help("Zoom the timeline out")
                SmoothSlider(value: $timelineZoom, in: 1 ... 10)
                    .frame(minWidth: 50, maxWidth: 100)
                    .help("Zoom the timeline (\(String(format: "%.0f×", timelineZoom)))")
                Button { withAnimation(Theme.swap) { timelineZoom = min(timelineZoom * 1.5, 10) } } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(IconButtonStyle(size: 24, iconSize: 12))
                .help("Zoom the timeline in")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func timecode(_ t: Double) -> some View {
        Text(format(t))
            .font(.rounded(14).monospacedDigit())
            .contentTransition(.numericText(value: t))
            .animation(.snappy(duration: 0.2), value: format(t))
    }
}

private struct PlayPauseGlyph: View {
    let playing: Bool

    var body: some View {
        ZStack {
            Image(systemName: "play.fill")
                .offset(x: 1.5)
                .scaleEffect(playing ? 0.4 : 1)
                .rotationEffect(.degrees(playing ? -90 : 0))
                .opacity(playing ? 0 : 1)
                .blur(radius: playing ? 3 : 0)
            Image(systemName: "pause.fill")
                .scaleEffect(playing ? 1 : 0.4)
                .rotationEffect(.degrees(playing ? 0 : 90))
                .opacity(playing ? 1 : 0)
                .blur(radius: playing ? 0 : 3)
        }
        .animation(.smooth(duration: 0.26), value: playing)
    }
}

struct PlayButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { PlayButtonBody(configuration: configuration) }
}

private struct PlayButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(Color.black.opacity(0.85))
            .frame(width: 40, height: 40)
            .background(Circle().fill(Color.white.opacity(hovering ? 1 : 0.92)))
            .shadow(color: .white.opacity(hovering ? 0.18 : 0), radius: 10)
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.9 : hovering ? 1.05 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.press, value: configuration.isPressed)
    }
}
