//
//  TranscriptView.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import AppKit
import SliceCore
import SwiftUI

struct TranscriptView: View {
    @ObservedObject var editor: EditorModel
    @State private var editing: TranscriptWord?
    @State private var editText = ""

    @AppStorage(TranscriptionPreferences.engineKey) private var engine: TranscriptionEngineKind = .appleSpeech

    private var language: String { Locale.current.languageName }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let p = editor.transcribeProgress {
                progress(p)
                Spacer()
            } else if editor.hasTranscript && editor.words.isEmpty {
                EmptyState(symbol: "waveform.slash", title: "No speech found",
                           message: editor.silentMicTakes.isEmpty
                               ? "The recording didn't contain recognisable speech."
                               : "The microphone recorded silence in take \(editor.silentMicTakes.map(String.init).joined(separator: ", ")). Check it's on, unmuted and connected before recording.")
                Spacer()
            } else if editor.hasTranscript {
                TranscriptLyrics(editor: editor) { w in
                    editText = w.word.text
                    editing = w
                }
            } else if editor.project.clips.allSatisfy({ $0.speechAudioFile == nil }) {
                EmptyState(symbol: "mic.slash", title: "No microphone",
                           message: "These takes have no microphone audio, so there's nothing to transcribe.")
                Spacer()
            } else {
                EmptyState(symbol: "text.quote", title: "Edit by text",
                           message: "Transcribe the recording, then cut the video by deleting words. Runs on this Mac with \(engine.displayName), in \(language).") {
                    VStack(spacing: 8) {
                        transcribeButton("Transcribe")
                        SettingsLink { Text("Change engine…").font(.system(size: 11)) }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            if let err = editor.transcribeError {
                VStack(alignment: .leading, spacing: 10) {
                    Text(err).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    if editor.transcribeNeedsSettings {
                        SettingsLink { Text("Open Settings") }.buttonStyle(PillButtonStyle())
                    }
                }
                .padding(16)
            }
        }
        .animation(Theme.swap, value: editor.transcribeProgress == nil)
        .animation(Theme.swap, value: editor.hasTranscript)
        .onChange(of: editing) { _, w in editor.isEditingText = w != nil }
        .alert("Edit word", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField("Word", text: $editText)
            Button("Save") {
                if let w = editing { editor.editWord(w, text: editText) }
                editing = nil
            }
            Button("Cancel", role: .cancel) { editing = nil }
        } message: {
            Text("Correct the transcription. This changes the subtitles, not the audio.")
        }
    }

    private func transcribeButton(_ title: String) -> some View {
        Button { editor.transcribe() } label: { Label(title, systemImage: "waveform") }
            .buttonStyle(PillButtonStyle(prominent: true))
    }

    private func progress(_ p: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Transcribing").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(Int(p * 100))%")
                    .font(.rounded(13).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: Int(p * 100))
                Button { editor.cancelTranscription() } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(size: 22, iconSize: 9))
                    .help("Stop transcribing. Takes already done are kept.")
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Theme.accent).frame(width: geo.size.width * p)
                }
            }
            .frame(height: 4)
            .animation(.smooth, value: p)
            Text(editor.transcribeNote ?? "Runs on this Mac with \((editor.transcribeEngine ?? engine).displayName).")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(2)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
        .padding(16)
    }
}

struct TranscriptBar: View {
    @ObservedObject var editor: EditorModel
    let playing: Bool

    var body: some View {
        let selection = editor.wordSelection
        let newTakes = !editor.untranscribedClips.isEmpty
        let shown = selection != nil || !playing || newTakes
        ZStack {
            if shown {
                content(selection, newTakes: newTakes)
                    .transition(.opacity.combined(with: .offset(y: 6)))
            }
        }
        .animation(Theme.swap, value: shown)
        .animation(Theme.swap, value: selection == nil)
    }

    private func content(_ selection: ClosedRange<Int>?, newTakes: Bool) -> some View {
        HStack(spacing: 6) {
            if let selection {
                Text(selection.count == 1 ? "1 word" : "\(selection.count) words")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                Spacer(minLength: 4)
                if editor.selectionHasCutWords {
                    Button { editor.restoreSelectedWords() } label: { Label("Put back", systemImage: "arrow.uturn.backward") }
                        .buttonStyle(PillButtonStyle())
                        .help("Put the cut words in the selection back")
                }
                if editor.selectionHasKeptWords {
                    Button { editor.deleteSelectedWords() } label: { Label("Cut", systemImage: "scissors") }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .help("Cut the selected words from the video (Delete)")
                }
                Button { editor.wordSelection = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(IconButtonStyle(size: 28, iconSize: 11))
                    .help("Clear the selection")
            } else {
                Text("Click a word to jump there. Drag to select.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.leading, 8)
                Spacer(minLength: 4)
                if newTakes {
                    Button { editor.transcribe() } label: { Label("New takes", systemImage: "waveform") }
                        .buttonStyle(PillButtonStyle())
                        .help("Transcribe takes added since")
                }
            }
        }
        .padding(5)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.window))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.stroke))
        .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
    }
}
