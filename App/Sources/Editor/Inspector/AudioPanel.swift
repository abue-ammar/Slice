//
//  AudioPanel.swift
//  Slice
//
//  Created by rit3zh CX on 10/10/26.
//

import SliceCore
import SwiftUI

struct AudioPanel: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var audition: MusicAudition
    @State private var chosenCategory: String?
    @State private var loading: MusicSource?

    static let importedCategory = "Imported"

    init(editor: EditorModel) {
        self.editor = editor
        audition = editor.audition
    }

    private var categories: [String] {
        let library = MusicLibrary.categories(of: EditorModel.libraryTracks)
        return library + [Self.importedCategory]
    }

    private var category: String {
        if let chosenCategory { return chosenCategory }
        switch editor.focusedMusic?.source {
        case let .library(id): return EditorModel.libraryTracks.first { $0.id == id }?.category ?? categories[0]
        case .file: return Self.importedCategory
        case nil: return categories[0]
        }
    }

    private var sources: [MusicSource] {
        category == Self.importedCategory
            ? editor.importedAudio.map(MusicSource.file)
            : EditorModel.libraryTracks.filter { $0.category == category }.map { .library($0.id) }
    }

    var body: some View {
        let current = editor.focusedMusic
        PanelSection("Background audio", trailing: AnyView(importButton)) {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(categories, id: \.self) { c in
                    ChoiceChip(title: c, selected: c == category) { withAnimation(Theme.swap) { chosenCategory = c } }
                }
            }
            ZStack(alignment: .topLeading) {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(sources, id: \.self) { source in
                        ChoiceChip(title: EditorModel.title(of: source), orb: source, selected: current?.source == source,
                                   busy: loading == source) { use(source) }
                    }
                    if category == Self.importedCategory {
                        ChoiceChip(title: "Add file…", symbol: "plus", selected: false) { editor.chooseMusicFiles() }
                    }
                }
                .id(category)
                .transition(.opacity)
            }
            .animation(Theme.swap, value: category)
            if let error = editor.audioError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .disabled(editor.duration <= 0)
        .dropDestination(for: URL.self) { urls, _ in
            Task { await editor.importMusic(urls) }
            return !urls.isEmpty
        }

        PanelDivider()

        if let current {
            AuditionButton(title: EditorModel.title(of: current.source), playing: audition.playing == current.source) {
                editor.toggleAudition(current.source)
            }
            PanelToggle("Mute background audio", isOn: $editor.project.audio.musicMuted)
            PanelSlider("Background audio volume", value: $editor.project.audio.musicVolume, in: 0 ... 1,
                        default: AudioSettings().musicVolume) { "\(Int(($0 * 100).rounded()))%" }
                .opacity(editor.project.audio.musicMuted ? 0.45 : 1)
                .animation(Theme.hover, value: editor.project.audio.musicMuted)
            PanelToggle("Even out loudness", isOn: $editor.project.audio.normalizeMusic)
                .help("Brings every track to the same loudness, so switching tracks keeps the level you set")
            Button {
                withAnimation(Theme.swap) { editor.removeAllMusic() }
            } label: {
                Label(editor.project.music.count > 1 ? "Remove all background audio" : "Remove background audio",
                      systemImage: "speaker.slash")
            }
            .buttonStyle(WideButtonStyle())
            if editor.project.music.count > 1 {
                PanelNote("\(editor.project.music.count) music clips are on the timeline. Click one to set its own fades and volume.")
            }
        } else {
            PanelNote(editor.duration > 0
                ? "Pick a track to play it under the whole video. It loops if the video is longer, and fades in and out. You can also drop audio files here."
                : "Record or add a clip first, then pick music to play under it.")
        }

        PanelDivider()
        DuckingSection(editor: editor)
        PanelDivider()
        AudioSection(editor: editor)
        PanelDivider()
        VoiceEnhancementSection(editor: editor)
    }

    private var importButton: some View {
        Button { editor.chooseMusicFiles() } label: { Image(systemName: "plus") }
            .buttonStyle(IconButtonStyle(size: 24, iconSize: 11))
            .disabled(editor.duration <= 0)
            .help("Import an audio file (MP3, M4A, WAV…). It's copied into the project.")
    }

    private func use(_ source: MusicSource) {
        loading = source
        Task {
            await editor.useMusic(source)
            if loading == source { loading = nil }
        }
    }
}

private struct DuckingSection: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let audio = editor.project.audio
        let d = AudioSettings()
        PanelSection("Auto ducking") {
            PanelToggle("Lower music while speaking", isOn: $editor.project.audio.ducking)
            if audio.ducking {
                Group {
                    PanelSlider("How much quieter", value: $editor.project.audio.duckAmount, in: 0.1 ... 0.95, default: d.duckAmount) {
                        "to \(Int(((1 - $0) * 100).rounded()))%"
                    }
                    .help("How far the music drops while someone speaks; the value is its level then")
                    MoreOptions(id: "ducking") {
                        PanelSlider("Fade down", value: $editor.project.audio.duckAttack, in: 0.05 ... 1.5, default: d.duckAttack) {
                            String(format: "%.2fs", $0)
                        }
                        .help("How long the music takes to drop. It starts early, so the first word is never covered.")
                        PanelSlider("Fade back up", value: $editor.project.audio.duckRelease, in: 0.1 ... 3, default: d.duckRelease) {
                            String(format: "%.1fs", $0)
                        }
                        .help("How long the music takes to come back after speech")
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                PanelNote(status)
            }
        }
        .animation(Theme.swap, value: audio.ducking)
    }

    private var status: String {
        let p = editor.project
        if !editor.hasSpeechAudio { return "These takes have no voice recording, so the music stays level." }
        if editor.isScanningSpeech { return "Listening for speech…" }
        if p.micVolume == 0 && p.clips.allSatisfy({ $0.micFile != nil }) { return "The microphone is muted, so the music stays level." }
        let spans = p.speechSpans
        if spans.isEmpty { return "No speech found: the voice track is silent or only background noise." }
        let total = spans.reduce(0) { $0 + $1.end - $1.start }
        return "Ducks under \(Int(total.rounded()))s of speech. The voice recording itself is untouched."
    }
}

// MARK: - Selected music clip

struct MusicInspector: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var audition: MusicAudition
    let clip: MusicClip

    init(editor: EditorModel, clip: MusicClip) {
        self.editor = editor
        self.clip = clip
        audition = editor.audition
    }

    private func bind<T>(_ keyPath: WritableKeyPath<MusicClip, T>) -> Binding<T> {
        Binding(get: { clip[keyPath: keyPath] }, set: { v in editor.updateMusic(clip.id) { $0[keyPath: keyPath] = v } })
    }

    var body: some View {
        let range = clip.timelineRange(duration: editor.duration)
        let missing = editor.musicURL(clip.source) == nil
        VStack(alignment: .leading, spacing: 18) {
            InfoRow(title: "Time", value: range.map { "\(format($0.lowerBound)) – \(format($0.upperBound))" } ?? "After the end")
            HStack(spacing: 8) {
                if missing {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else {
                    MusicOrb(source: clip.source, drifting: audition.playing == clip.source).frame(width: 30, height: 30)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(clip.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Text(missing ? "File missing. Choose it again or pick another track." : sourceKind)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                replaceMenu
            }
            if missing {
                Button { editor.chooseReplacement(for: clip.id) } label: { Label("Locate file…", systemImage: "folder") }
                    .buttonStyle(WideButtonStyle())
            } else {
                AuditionButton(title: clip.name, playing: audition.playing == clip.source) { editor.toggleAudition(clip.source) }
            }

            PanelSection("Level") {
                PanelSlider("Clip volume", value: bind(\.volume), in: 0 ... 1, default: 1) {
                    $0 > 0 ? "\(Int(($0 * 100).rounded()))%" : "Muted"
                }
                .help("This clip's level, on top of the background audio volume")
            }
            PanelSection("Fades") {
                PanelSlider("Fade in", value: bind(\.fadeIn), in: 0 ... 5, default: 1) { $0 < 0.03 ? "Off" : String(format: "%.1fs", $0) }
                PanelSlider("Fade out", value: bind(\.fadeOut), in: 0 ... 5, default: 2) { $0 < 0.03 ? "Off" : String(format: "%.1fs", $0) }
                PanelNote("Even with fades off, the music eases in and out over a moment so it never clicks.")
            }
            PanelSection("Length") {
                PanelToggle("Loop to fill", isOn: Binding(get: { clip.loops }, set: { on in
                    editor.updateMusic(clip.id) { c in
                        if !on { c.offset = min(c.offset, max(c.sourceDuration - MusicClip.minLength, 0)) }
                        c.loops = on
                    }
                }))
                .help("Repeats the track, crossfading each repeat into the next")
                PanelToggle("Play to the end of the video", isOn: Binding(get: { clip.toEnd }, set: { on in
                    let end = clip.nominalEnd(duration: editor.duration)
                    editor.updateMusic(clip.id) { c in
                        c.toEnd = on
                        if !on { c.end = min(end, editor.duration) }
                        if on, c.sourceDuration - c.offset < editor.duration - c.start { c.loops = true }
                    }
                }))
                .help("Keeps reaching the end as the video gets longer or shorter")
                PanelNote("Drag the clip on the timeline to move it, or its edges to trim it.")
            }
            Button("Remove music") { editor.removeMusic(clip.id) }.buttonStyle(DestructiveButtonStyle())
        }
    }

    private var sourceKind: String {
        switch clip.source {
        case .library: "Library · \(format(clip.sourceDuration))"
        case .file: "Imported · \(format(clip.sourceDuration))"
        }
    }

    private var replaceMenu: some View {
        Menu {
            ForEach(MusicLibrary.categories(of: EditorModel.libraryTracks), id: \.self) { category in
                Section(category) {
                    ForEach(EditorModel.libraryTracks.filter { $0.category == category }) { t in
                        Button(t.title) { Task { await editor.replaceMusic(clip.id, with: .library(t.id)) } }
                    }
                }
            }
            if !editor.importedAudio.isEmpty {
                Section(AudioPanel.importedCategory) {
                    ForEach(editor.importedAudio, id: \.self) { rel in
                        Button(EditorModel.title(of: .file(rel))) { Task { await editor.replaceMusic(clip.id, with: .file(rel)) } }
                    }
                }
            }
            Divider()
            Button("Choose File…") { editor.chooseReplacement(for: clip.id) }
        } label: {
            Text("Replace")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PillButtonStyle())
        .fixedSize()
        .help("Play another track here, keeping the clip's place and length")
    }
}

// MARK: - Controls

struct ChoiceChip: View {
    let title: String
    var symbol: String?
    var orb: MusicSource?
    let selected: Bool
    var busy = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if busy {
                    ProgressView().controlSize(.mini).transition(.opacity)
                } else if let orb {
                    MusicOrb(source: orb).frame(width: 14, height: 14)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                }
                Text(title)
            }
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(selected || hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 13)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Theme.thumb : hovering ? Theme.controlHover : Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(selected ? 0.16 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(ChipPress())
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .animation(Theme.hover, value: selected)
        .animation(Theme.hover, value: busy)
    }
}

private struct ChipPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

struct AuditionButton: View {
    let title: String
    let playing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: playing ? "stop.circle" : "play.circle")
                    .font(.system(size: 16, weight: .regular))
                    .contentTransition(.symbolEffect(.replace))
                Text(playing ? "Stop \(title)" : "Play \(title)")
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(WideButtonStyle())
        .animation(Theme.swap, value: playing)
        .help(playing ? "Stop listening" : "Listen to this track on its own")
    }
}

struct WideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { WideButtonBody(configuration: configuration) }
}

private struct WideButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 38)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Theme.controlHover : Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 && isEnabled }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.press, value: configuration.isPressed)
    }
}
