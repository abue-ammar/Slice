//
//  VoiceEnhancementSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import SliceCore
import SwiftUI

struct VoiceEnhancementSection: View {
    @ObservedObject var editor: EditorModel
    @ObservedObject private var store = VoiceModelStore.shared
    @State private var confirmRemove = false

    var body: some View {
        let voice = editor.project.voice
        PanelSection("Voice enhancement", trailing: AnyView(toggle)) {
            if !editor.hasMicrophone {
                PanelNote("These takes have no microphone recording to enhance.")
            } else {
                Group {
                    if voice.enhance {
                        Group {
                            compare
                            PanelSlider("Noise removal", value: $editor.project.voice.noiseReduction, in: 12 ... VoiceSettings.fullReduction,
                                        default: VoiceSettings.fullReduction) {
                                $0 >= VoiceSettings.fullReduction - 0.5 ? "Full" : "\(Int($0.rounded())) dB"
                            }
                            .help("How far background noise is pushed down. Less leaves a trace of the room, which can sound more natural.")
                            PanelToggle("Podcast polish", isOn: $editor.project.voice.polish)
                                .help("Gentle EQ, compression and loudness for a clear, even voice")
                            MoreOptions(id: "voice") {
                                Group {
                                    PanelToggle("Voice EQ", isOn: $editor.project.voice.eq)
                                        .help("Cuts rumble and boxiness, adds a little presence and air")
                                    PanelToggle("Even out loud and quiet words", isOn: $editor.project.voice.compress)
                                        .help("Gentle 2:1 compression")
                                    PanelToggle("Podcast loudness", isOn: $editor.project.voice.normalize)
                                        .help("Brings every take to −16 LUFS, the usual level for podcasts and video")
                                }
                                .disabled(!voice.polish)
                                .opacity(voice.polish ? 1 : 0.45)
                                .animation(Theme.hover, value: voice.polish)
                                modelRow
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    status
                }
            }
        }
        .animation(Theme.swap, value: voice.enhance)
        .animation(Theme.swap, value: editor.voiceProgress == nil)
        .sheet(isPresented: $editor.showVoiceModelSheet) {
            VoiceModelSheet(store: store) { editor.voiceModelInstalled() }
        }
        .confirmationDialog("Remove the voice model?", isPresented: $confirmRemove) {
            Button("Remove Model", role: .destructive) { store.remove() }
        } message: {
            Text("Voices already enhanced keep playing. New takes need the model again (\(Self.size(VoiceModel.downloadBytes)) download).")
        }
    }

    private var toggle: some View {
        Toggle("Enhance voice", isOn: Binding(get: { editor.project.voice.enhance },
                                              set: { on in withAnimation(Theme.swap) { editor.setVoiceEnhancement(on) } }))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .tint(Theme.accent)
            .disabled(!editor.hasMicrophone)
            .help("Enhance voice")
    }

    private var compare: some View {
        HStack(spacing: 6) {
            Text("Listen to").font(.system(size: 13))
            Spacer()
            ChoiceChip(title: "Original", selected: editor.hearOriginalVoice) { editor.hearOriginalVoice = true }
            ChoiceChip(title: "Enhanced", selected: !editor.hearOriginalVoice) { editor.hearOriginalVoice = false }
        }
        .disabled(editor.voiceProgress != nil || !editor.voicePending.isEmpty)
        .help("Switch between the recording as it was and the enhanced voice while the preview plays")
    }

    @ViewBuilder private var status: some View {
        if let error = editor.voiceError {
            VStack(alignment: .leading, spacing: 10) {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if !store.isInstalled, editor.needsVoiceModel {
                    Button("Download Model…") { editor.showVoiceModelSheet = true }.buttonStyle(PillButtonStyle())
                } else {
                    Button("Try Again") { editor.voiceError = nil; editor.scheduleVoice(rebuildIfReady: true) }
                        .buttonStyle(PillButtonStyle())
                }
            }
            .transition(.opacity)
        } else if let progress = editor.voiceProgress {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("Enhancing voice on this Mac…").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int((progress * 100).rounded(.down)))%")
                        .font(.rounded(12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: progress))
                }
                ProgressView(value: progress).progressViewStyle(.linear).tint(Theme.accent).controlSize(.small)
            }
            .animation(.smooth(duration: 0.25), value: progress)
            .transition(.opacity)
        } else if editor.project.voice.enhance {
            PanelNote("Background noise removed on this Mac with DeepFilterNet3. Your original recording is kept, and exports use the enhanced voice.")
        } else {
            PanelNote(store.isInstalled
                ? "Removes background noise from your microphone for a clean, podcast-style voice. Runs on this Mac."
                : "Removes background noise from your microphone for a clean, podcast-style voice. Runs on this Mac, after a one-time \(Self.size(VoiceModel.downloadBytes)) download.")
        }
    }

    private var modelRow: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(VoiceModel.displayName) model").font(.system(size: 13))
                Text(store.isInstalled ? "\(Self.size(VoiceModel.installedBytes)) on this Mac" : "Not downloaded")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.isInstalled {
                Button("Remove") { confirmRemove = true }.buttonStyle(PillButtonStyle())
                    .help("Delete the model from this Mac")
            } else {
                Button("Download…") { editor.showVoiceModelSheet = true }.buttonStyle(PillButtonStyle())
            }
        }
    }

    static func size(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}

struct VoiceModelSheet: View {
    @ObservedObject var store: VoiceModelStore
    let installed: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "waveform")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Enhance your voice").font(.system(size: 17, weight: .semibold))
                    Text("Voice enhancement needs a small model, downloaded once.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 11) {
                point("waveform.path", "Removes fans, hum, hiss and room noise while keeping your voice natural.")
                point("slider.horizontal.3", "Optional podcast polish: gentle EQ, compression and even loudness.")
                point("lock.shield", "Runs entirely on this Mac. Your audio is never uploaded, and it works offline after the download.")
                point("arrow.uturn.backward", "Your original recording is always kept. Turn enhancement off to hear it again.")
            }

            VStack(spacing: 7) {
                detail("Model", "\(VoiceModel.displayName), standard")
                detail("Download", VoiceEnhancementSection.size(VoiceModel.downloadBytes))
                detail("Storage", "\(VoiceEnhancementSection.size(VoiceModel.downloadBytes)) in Application Support")
                detail("Source", "DeepFilterNet project, \(VoiceModel.license)")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.05)))

            progress

            HStack(spacing: 10) {
                Link("About DeepFilterNet", destination: VoiceModel.sourceURL).font(.system(size: 12))
                Spacer()
                if store.isDownloading {
                    Button("Cancel Download") { store.cancel() }
                } else {
                    Button("Not Now") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(isFailed ? "Try Again" : "Download Model") { store.download() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 460)
        .interactiveDismissDisabled(store.isDownloading)
        .animation(.smooth(duration: 0.25), value: store.state)
        .onChange(of: store.state) { _, state in
            if state == .installed {
                installed()
                dismiss()
            }
        }
    }

    private var isFailed: Bool { if case .failed = store.state { true } else { false } }

    @ViewBuilder private var progress: some View {
        switch store.state {
        case let .downloading(received, total):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: Double(received), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(Theme.accent)
                Text(received >= total
                    ? "Checking the files and testing the model…"
                    : "\(VoiceEnhancementSection.size(received)) of \(VoiceEnhancementSection.size(total))")
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        case let .failed(message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.system(size: 12))
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity)
        case .notInstalled, .installed:
            EmptyView()
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 18)
            Text(text).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.system(size: 12))
    }
}
