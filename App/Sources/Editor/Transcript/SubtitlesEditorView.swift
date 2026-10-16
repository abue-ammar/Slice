//
//  SubtitlesEditorView.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import AppKit
import SliceCore
import SwiftUI

struct SubtitleSettingsView: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let subs = editor.project.subtitles
        let keys = editor.project.keystrokes
        PanelSection("Subtitles", trailing: AnyView(exportButton)) {
            SubtitlePreview(settings: subs, shortcuts: keys.visible && editor.hasKeystrokes && keys.position.rawValue == subs.position.rawValue)
            PanelToggle("Show in video", isOn: $editor.project.subtitles.burnIn)
            if subs.burnIn {
                SegmentedControl(selection: $editor.project.subtitles.position, options: [.bottom, .top],
                                 title: { $0 == .bottom ? "Bottom" : "Top" })
                PanelSlider("Size", value: $editor.project.subtitles.size, in: 0.03 ... 0.08) { percent($0, of: 0.03 ... 0.08) }
                PanelToggle("Word by word", isOn: $editor.project.subtitles.highlightWord)
                    .help("Each word waits dim, and lights up as it's said.")
            }
        }
        .animation(Theme.swap, value: subs.burnIn)
    }

    private var exportButton: some View {
        Button { editor.exportSRT() } label: { Image(systemName: "square.and.arrow.down") }
            .buttonStyle(IconButtonStyle(size: 24, iconSize: 12))
            .disabled(editor.captions.isEmpty)
            .help("Export subtitles (.srt)…")
    }
}

private struct SubtitlePreview: View {
    let settings: SubtitleSettings
    let shortcuts: Bool
    @State private var line = 0
    @State private var said = 0

    private static let lines = [["So", "this", "is", "the", "dashboard"], ["and", "every", "citation", "we", "tracked"]]

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let bottom = settings.position == .bottom
        ZStack(alignment: bottom ? .bottom : .top) {
            shape.fill(Color.white.opacity(0.025))
            VStack(alignment: .leading, spacing: 7) {
                Capsule().frame(width: 92, height: 5)
                Capsule().frame(width: 140, height: 5)
                Capsule().frame(width: 64, height: 5)
            }
            .foregroundStyle(Color.white.opacity(0.05))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 18)
            if settings.burnIn {
                VStack(spacing: 6) {
                    if bottom && shortcuts { keys }
                    caption
                    if !bottom && shortcuts { keys }
                }
                .padding(.vertical, 12)
                .transition(.opacity)
            }
        }
        .frame(height: 112)
        .overlay(shape.strokeBorder(Theme.stroke))
        .animation(Theme.slide, value: settings.position)
        .animation(Theme.swap, value: shortcuts)
        .task(id: settings.burnIn) {
            while settings.burnIn && !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.3))
                guard !Task.isCancelled else { return }
                if said < Self.lines[line % Self.lines.count].count + 3 {
                    said += 1
                } else {
                    line += 1
                    said = 1
                }
            }
        }
    }

    private var caption: some View {
        let words = Self.lines[line % Self.lines.count]
        return HStack(spacing: 3.5) {
            ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                let on: Bool = !settings.highlightWord || i < said
                Text(word)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .opacity(on ? 1 : 0.42)
                    .animation(.easeInOut(duration: 0.28), value: on)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.black.opacity(0.7)))
        .id(line)
        .transition(.asymmetric(
            insertion: .modifier(active: CaptionFocus(blur: 4, opacity: 0, scale: 0.92), identity: CaptionFocus(blur: 0, opacity: 1, scale: 1))
                .animation(.spring(response: 0.34, dampingFraction: 0.76)),
            removal: .modifier(active: CaptionFocus(blur: 4, opacity: 0, scale: 0.97), identity: CaptionFocus(blur: 0, opacity: 1, scale: 1))
                .animation(.easeIn(duration: 0.18))))
    }

    private var keys: some View {
        HStack(spacing: 3) {
            ForEach(["⌘", "K"], id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(minWidth: 18, minHeight: 18)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(white: 0.15)))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
            }
        }
        .transition(.opacity)
    }
}

private struct CaptionFocus: ViewModifier {
    let blur: CGFloat
    let opacity: Double
    let scale: CGFloat

    func body(content: Content) -> some View {
        content.blur(radius: blur).scaleEffect(scale).opacity(opacity)
    }
}

struct SubtitlesEditorView: View {
    @ObservedObject private var clock: PlaybackClock
    @ObservedObject var editor: EditorModel
    @FocusState private var focused: Double?
    @State private var drafts: [Double: String] = [:]

    init(editor: EditorModel) {
        self.editor = editor
        clock = editor.clock
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if editor.captions.isEmpty {
                EmptyState(symbol: "captions.bubble", title: "No subtitles yet",
                           message: editor.hasTranscript ? "The transcript has no words to make subtitles from."
                               : "Subtitles are made from the transcript. Transcribe in the Transcript tab first.")
                Spacer()
            } else {
                SubtitleSettingsView(editor: editor).padding(18)
                Rectangle().fill(Theme.stroke).frame(height: 1)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(editor.captions, id: \.start) { caption in
                                row(caption)
                            }
                        }
                        .padding(10)
                    }
                    .scrollIndicators(.never)
                    .onChange(of: currentCaptionStart) { _, start in
                        if editor.isPlaying, let start { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(start, anchor: .center) } }
                    }
                }
            }
        }
        .onChange(of: focused) { old, new in
            if let old, old != new, let c = editor.captions.first(where: { $0.start == old }) { commit(c) }
            editor.isEditingText = new != nil
        }
        .onAppear {
            // macOS focuses the first text field on appear; don't grab the keyboard until a line is clicked.
            DispatchQueue.main.async { focused = nil }
        }
        .onDisappear { editor.isEditingText = false }
    }

    private var currentCaptionStart: Double? { CaptionBuilder.caption(at: editor.time, in: editor.captions)?.start }

    private func row(_ caption: Caption) -> some View {
        let isCurrent = currentCaptionStart == caption.start
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(format(caption.start)) { editor.seek(to: caption.start) }
                .buttonStyle(.borderless)
                .font(.rounded(11).monospacedDigit())
                .foregroundStyle(isCurrent ? Theme.accent : .secondary)
                .help("Jump here")
            TextField("", text: Binding(get: { drafts[caption.start] ?? caption.text },
                                        set: { drafts[caption.start] = $0 }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .focused($focused, equals: caption.start)
                .onSubmit { commit(caption) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(isCurrent ? Theme.accent.opacity(0.12) : focused == caption.start ? Theme.control : .clear))
        .animation(Theme.hover, value: isCurrent)
        .animation(Theme.hover, value: focused == caption.start)
        .id(caption.start)
    }

    private func commit(_ caption: Caption) {
        guard let text = drafts.removeValue(forKey: caption.start), text != caption.text else { return }
        editor.applySubtitleEdit(caption, text: text)
    }
}
