//
//  EditorView.swift
//  Slice
//
//  Created by rit3zh CX on 10/9/26.
//

import AVFoundation
import SliceCore
import SwiftUI

struct EditorView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var editor: EditorModel
    @State private var showExport = false
    @State private var timelineZoom = 1.0
    @State private var showPalette = false
    @State private var toast: (id: UUID, title: String, keys: [String])?
    @AppStorage("sidePanel.tab") private var inspectorTab = InspectorTab.frame.rawValue

    var body: some View {
        VStack(spacing: 0) {
            EditorTitleBar(editor: editor, isExporting: isExporting, openPalette: { showPalette = true }, openExport: openExport)
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    PreviewHeader(editor: editor)
                    PreviewArea(editor: editor)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                            ProjectFaces.shared.measuredPreviewArea($0)
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                    TransportBar(editor: editor, timelineZoom: $timelineZoom)
                }
                .frame(minWidth: 520)
                .overlay(alignment: .bottom) {
                    ZStack {
                        if let toast {
                            ShortcutToast(title: toast.title, keys: toast.keys)
                                .id(toast.id)
                                .transition(.toast)
                        }
                    }
                    .padding(.bottom, 64)
                    .animation(.smooth(duration: 0.35), value: toast?.id)
                    .allowsHitTesting(false)
                }
                SidePanel(editor: editor)
                    .frame(width: 390)
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.top, 8)
            .padding(.bottom, 10)
            TimelineView(editor: editor, zoom: $timelineZoom)
                .frame(height: 334 + (editor.shows3DTrack ? 46 : 0) + (editor.hasAnnotations ? 46 : 0))
                .animation(Theme.slide, value: editor.shows3DTrack)
                .animation(Theme.slide, value: editor.hasAnnotations)
        }
        .overlay {
            CommandPaletteLayer(isPresented: showPalette, commands: commands, close: { showPalette = false }) { cmd in
                showPalette = false
                DispatchQueue.main.asyncAfter(deadline: .now() + CommandPaletteLayer.hideDuration) {
                    cmd.run()
                    if !cmd.keys.isEmpty { showToast(cmd) }
                }
            }
        }
        .overlay {
            ExportLayer(job: editor.exportJob, stop: editor.stopExport, close: editor.dismissExport)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .navigationTitle(editor.project.name)
        .onDrop(of: [.movie, .audio, .fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for p in providers {
                    if let url = try? await p.loadItem(forTypeIdentifier: "public.file-url") as? Data,
                       let u = URL(dataRepresentation: url, relativeTo: nil) { urls.append(u) }
                }
                if let other = urls.first(where: ProjectBundle.isProject) {
                    model.openFiles([other])
                    return
                }
                let isAudio: (URL) -> Bool = { UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audio) ?? false }
                let audio = urls.filter(isAudio)
                if !audio.isEmpty {
                    show(.audio)
                    await editor.importMusic(audio)
                }
                let videos = urls.filter { !isAudio($0) }
                if !videos.isEmpty { await editor.importClips(videos) }
            }
            return true
        }
        .sheet(isPresented: $showExport) { ExportSheet(editor: editor) }
        .background { shortcuts }
    }

    @ViewBuilder private var shortcuts: some View {
        Button("") { showPalette.toggle() }.keyboardShortcut("k", modifiers: .command).hidden()
            .disabled(isExporting)
        Group {
            Button("") { editor.deleteSelection() }.keyboardShortcut(.delete, modifiers: []).hidden()
                .disabled(editor.isEditingText)
            Button("") { editor.togglePlay() }.keyboardShortcut(.space, modifiers: []).hidden()
                .disabled(editor.isEditingText)
            Button("") { editor.splitAtPlayhead() }.keyboardShortcut("b", modifiers: .command).hidden()
            Button("") { editor.isCutting = false }.keyboardShortcut(.escape, modifiers: []).hidden()
                .disabled(!editor.isCutting)
            Button("") { editor.undo() }.keyboardShortcut("z", modifiers: .command).hidden()
            Button("") { editor.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).hidden()
            Button("") { openExport() }.keyboardShortcut("e", modifiers: [.command, .shift]).hidden()
            Button("") { zoomTimeline(by: 1.5) }.keyboardShortcut("=", modifiers: .command).hidden()
            Button("") { zoomTimeline(by: 1 / 1.5) }.keyboardShortcut("-", modifiers: .command).hidden()
            Button("") { withAnimation(Theme.swap) { timelineZoom = 1 } }.keyboardShortcut("0", modifiers: .command).hidden()
            ForEach(Array(InspectorTab.allCases.enumerated()).filter { $0.element.isAvailable(in: editor.project) }, id: \.offset) { i, tab in
                Button("") { show(tab) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command).hidden()
            }
        }
        .disabled(showPalette || isExporting)
    }

    private var isExporting: Bool { editor.exportJob != nil }

    private func openExport() {
        editor.pause()
        showExport = true
    }

    private func zoomTimeline(by factor: Double) {
        withAnimation(Theme.swap) { timelineZoom = min(max(timelineZoom * factor, 1), 10) }
    }

    private func show(_ tab: InspectorTab) {
        withAnimation(Theme.slide) {
            inspectorTab = tab.rawValue
            editor.selection = nil
        }
    }

    private func showToast(_ cmd: EditorCommand) {
        let id = UUID()
        toast = (id, cmd.title, cmd.keys)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            if toast?.id == id { toast = nil }
        }
    }

    private var commands: [EditorCommand] {
        var list: [EditorCommand] = [
            EditorCommand(id: "play", title: editor.isPlaying ? "Pause" : "Play", symbol: "playpause", group: .playback,
                          keys: ["Space"], keywords: "start stop") { editor.togglePlay() },
            EditorCommand(id: "start", title: "Go to start", symbol: "backward.end", group: .playback,
                          keywords: "beginning rewind") { editor.seek(to: 0) },
            EditorCommand(id: "end", title: "Go to end", symbol: "forward.end", group: .playback) { editor.seek(to: editor.duration) },
        ]
        for (rate, symbol) in [(Float(0.5), "tortoise"), (1, "gauge.with.needle"), (1.5, "hare"), (2, "hare")] {
            list.append(EditorCommand(id: "rate\(rate)", title: rate == 1 ? "Normal speed" : String(format: "Play at %g×", rate),
                                      detail: editor.playbackRate == rate ? "Current" : "Preview only", symbol: symbol,
                                      group: .playback, keywords: "speed rate slow fast") { editor.playbackRate = rate })
        }
        list += [
            EditorCommand(id: "undo", title: "Undo", symbol: "arrow.uturn.backward", group: .edit, keys: ["⌘", "Z"],
                          enabled: editor.canUndo) { editor.undo() },
            EditorCommand(id: "redo", title: "Redo", symbol: "arrow.uturn.forward", group: .edit, keys: ["⇧", "⌘", "Z"],
                          enabled: editor.canRedo) { editor.redo() },
            EditorCommand(id: "split", title: "Split at playhead", symbol: "scissors", group: .edit, keys: ["⌘", "B"],
                          keywords: "cut clip") { editor.splitAtPlayhead() },
            EditorCommand(id: "cuttool", title: editor.isCutting ? "Stop cutting" : "Cut tool",
                          detail: "Click a clip to split it there", symbol: "scissors", group: .edit,
                          keywords: "split blade razor scissors") { editor.toggleCutting() },
            EditorCommand(id: "delete", title: "Delete selection", symbol: "trash", group: .edit, keys: ["⌫"],
                          keywords: "remove", enabled: editor.selection != nil) { editor.deleteSelection() },
            EditorCommand(id: "autozoom", title: "Smart zoom", detail: "Clicks, typing and pauses", symbol: "sparkle.magnifyingglass",
                          group: .edit, keywords: "auto suggest zooms analyse",
                          enabled: editor.hasPointerLog && editor.smartZoomProgress == nil) { editor.autoZoom() },
            EditorCommand(id: "quiet", title: "Speed up quiet moments", detail: "Idle and typing", symbol: "hare",
                          group: .edit, keywords: "fast forward skip boring idle typing timelapse",
                          enabled: editor.hasPointerLog) { editor.speedUpQuietMoments(QuietMoments.Settings.saved) },
            EditorCommand(id: "sensitive", title: "Find sensitive text", detail: "Emails, cards, keys", symbol: "eye.slash",
                          group: .edit, keywords: "blur redact privacy hide password email api key",
                          enabled: editor.privacyScanProgress == nil) { editor.findSensitiveText() },
            EditorCommand(id: "addblur", title: "Add blur at playhead", symbol: "eye.slash", group: .timeline,
                          keywords: "redact pixelate hide privacy") { editor.addRedaction(at: editor.time) },
            EditorCommand(id: "addspotlight", title: "Add spotlight at playhead", symbol: SpotlightLane.symbol, group: .timeline,
                          keywords: "focus highlight dim blur circle") { editor.addSpotlight(at: editor.time) },
            EditorCommand(id: "draw", title: AnnotationController.shared.session.isActive ? "Stop drawing on screen" : "Draw on screen",
                          detail: "Before or while recording", symbol: AnnotationLane.symbol, group: .view,
                          keys: AnnotationController.toggleKeys, keywords: "annotate annotation pen marker highlight arrow markup",
                          enabled: AnnotationController.shared.isAvailable) { AnnotationController.shared.toggleDrawing() },
            EditorCommand(id: "selectdrawing", title: "Select drawing at playhead", symbol: AnnotationLane.symbol, group: .timeline,
                          keywords: "annotation markup pen arrow", enabled: editor.hasAnnotations) { editor.selectAnnotation(near: editor.time) },
            EditorCommand(id: "addzoom", title: "Add zoom at playhead", symbol: "plus.magnifyingglass", group: .timeline,
                          keywords: "block") { editor.addZoomBlock(at: editor.time) },
            EditorCommand(id: "addcamera", title: "Add camera layout at playhead", symbol: "person.crop.rectangle",
                          group: .timeline, keywords: "webcam block") { editor.addCameraBlock(at: editor.time) },
            EditorCommand(id: "addmusic", title: "Add music at playhead", symbol: "music.note", group: .timeline,
                          keywords: "audio song background soundtrack") { Task { await editor.addMusicClip(at: editor.time) } },
            EditorCommand(id: "importmusic", title: "Import music…", symbol: "music.note.list", group: .project,
                          keywords: "audio song mp3 wav m4a background soundtrack") {
                show(.audio)
                editor.chooseMusicFiles()
            },
            EditorCommand(id: "mutemusic", title: editor.project.audio.musicMuted ? "Unmute background music" : "Mute background music",
                          symbol: editor.project.audio.musicMuted ? "speaker.wave.2" : "speaker.slash", group: .edit,
                          keywords: "audio song silence", enabled: !editor.project.music.isEmpty) {
                editor.project.audio.musicMuted.toggle()
            },
            EditorCommand(id: "tlin", title: "Zoom timeline in", symbol: "plus.magnifyingglass", group: .timeline,
                          keys: ["⌘", "="], keywords: "magnify") { zoomTimeline(by: 1.5) },
            EditorCommand(id: "tlout", title: "Zoom timeline out", symbol: "minus.magnifyingglass", group: .timeline,
                          keys: ["⌘", "−"]) { zoomTimeline(by: 1 / 1.5) },
            EditorCommand(id: "tlfit", title: "Fit timeline", symbol: "arrow.left.and.right", group: .timeline,
                          keys: ["⌘", "0"], keywords: "reset whole") { withAnimation(Theme.swap) { timelineZoom = 1 } },
        ]
        for (i, tab) in InspectorTab.allCases.enumerated() where tab.isAvailable(in: editor.project) {
            list.append(EditorCommand(id: "tab-\(tab.rawValue)", title: "Show \(tab.title)", symbol: tab.symbol, group: .panels,
                                      keys: ["⌘", "\(i + 1)"], keywords: "inspector settings tab") { show(tab) })
        }
        if editor.project.hasDeviceRecording {
            let on = editor.project.device3D.enabled
            list.append(EditorCommand(id: "device3d", title: on ? "Show the iPhone flat" : "Show the iPhone in 3D", symbol: "cube",
                                      group: .view, keywords: "3d mockup phone device tilt") {
                withAnimation(.snappy) { editor.project.device3D.enabled.toggle() }
                if !on { show(.device3D) }
            })
        }
        for aspect in OutputAspect.allCases {
            list.append(EditorCommand(id: "aspect-\(aspect.rawValue)", title: "\(aspect.name) frame",
                                      detail: aspect == .auto ? "Match recording" : aspect.rawValue, symbol: aspect.symbol,
                                      group: .view, keywords: "aspect ratio shape") {
                withAnimation(.snappy) { editor.project.export.aspect = aspect }
            })
        }
        list += [
            EditorCommand(id: "export", title: "Export…", symbol: "square.and.arrow.up", group: .project,
                          keys: ["⇧", "⌘", "E"], keywords: "render save video gif") { openExport() },
            EditorCommand(id: "srt", title: "Export subtitles…", detail: ".srt", symbol: "captions.bubble", group: .project,
                          enabled: !editor.captions.isEmpty) { editor.exportSRT() },
            EditorCommand(id: "transcribe", title: "Transcribe", symbol: "waveform", group: .project, keywords: "speech text",
                          enabled: !editor.untranscribedClips.isEmpty && editor.transcribeProgress == nil) {
                show(.transcript)
                editor.transcribe()
            },
            EditorCommand(id: "addclip", title: "Add clip…", symbol: "plus.rectangle.on.rectangle", group: .project,
                          keywords: "import video") { importInto(editor) },
            EditorCommand(id: "record", title: "Record another take", symbol: "record.circle", group: .project) {
                editor.close()
                model.newRecording(appendTo: editor)
            },
            EditorCommand(id: "projects", title: "Back to projects", symbol: "chevron.left", group: .project, keywords: "home close") {
                editor.close()
                model.show(.home)
            },
        ]
        return list
    }
}

@MainActor
func importInto(_ editor: EditorModel) {
    guard let urls = chooseVideos() else { return }
    Task { await editor.importClips(urls) }
}

@MainActor
func chooseVideos() -> [URL]? {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.movie]
    panel.allowsMultipleSelection = true
    panel.message = "Choose videos to add. They're copied into the project."
    return panel.runModal() == .OK && !panel.urls.isEmpty ? panel.urls : nil
}
