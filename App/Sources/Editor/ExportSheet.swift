//
//  ExportSheet.swift
//  Slice
//
//  Created by rit3zh CX on 10/9/26.
//

import SliceCore
import SwiftUI

struct ExportSheet: View {
    @ObservedObject var editor: EditorModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("export.allShapes") private var allShapes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.title2.weight(.semibold))
            Form {
                LabeledContent("Made for") { ExportPresetMenu(editor: editor) }
                Picker("Format", selection: $editor.project.export.format) {
                    ForEach(ExportFormat.allCases, id: \.self) { Text($0.label) }
                }
                Toggle("All three shapes (16:9, 9:16 and 1:1)", isOn: $allShapes)
                    .help("Writes one file per shape from the same edit, into a folder you choose")
                if !allShapes {
                    Picker("Aspect ratio", selection: $editor.project.export.aspect) {
                        ForEach(OutputAspect.allCases, id: \.self) { Text($0.menuTitle) }
                    }
                }
                if editor.project.export.format == .gif {
                    GIFSettingsFields(editor: editor)
                } else {
                    OutputSettingsFields(editor: editor)
                }
                if !editor.captions.isEmpty {
                    Toggle("Burn in subtitles", isOn: $editor.project.subtitles.burnIn)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button(allShapes ? "Export 3 Files…" : "Export…") { allShapes ? chooseFolderAndExport() : chooseAndExport() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
        .animation(.snappy, value: allShapes)
    }

    private func chooseFolderAndExport() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose where to save the 16:9, 9:16 and 1:1 files."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        dismiss()
        editor.startBatchExport(in: folder)
    }

    private func chooseAndExport() {
        let panel = NSSavePanel()
        let format = editor.project.export.format
        panel.allowedContentTypes = [format == .gif ? .gif : .mpeg4Movie]
        let size = editor.project.exportSize
        panel.nameFieldStringValue = "\(editor.project.name) \(Int(size.width))x\(Int(size.height)).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        dismiss()
        editor.startExport(to: url)
    }
}

struct OutputSettingsFields: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        Picker("Resolution", selection: $editor.project.export.resolution) {
            ForEach(OutputResolution.allCases, id: \.self) { Text($0.label) }
        }
        Picker("Frame rate", selection: $editor.project.export.fps) {
            Text("30 fps").tag(30)
            Text("60 fps").tag(60)
            Text("120 fps").tag(120)
        }
        Picker("Quality", selection: $editor.project.export.quality) {
            ForEach(ExportQuality.allCases, id: \.self) { Text($0.label) }
        }
        Picker("Codec", selection: $editor.project.export.hevc) {
            Text("HEVC (smaller)").tag(true)
            Text("H.264 (most compatible)").tag(false)
        }
        LabeledContent("Output") {
            let s = editor.project.renderSize
            let mbps = Double(editor.project.exportBitRate) / 1_000_000
            Text("\(Int(s.width)) × \(Int(s.height)) · \(ExportSheet.rate(mbps))").monospacedDigit()
        }
        if let limit = editor.project.export.sizeLimitMB {
            LabeledContent("File size") {
                HStack(spacing: 6) {
                    Text("Under \(limit) MB")
                    Button { editor.project.export.sizeLimitMB = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("No size limit")
                }
            }
            let s = editor.project.renderSize
            if min(s.width, s.height) < CGFloat(editor.project.export.resolution.rawValue) {
                Text("Lowered from \(editor.project.export.resolution.label) to fit \(limit) MB.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

struct GIFSettingsFields: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        Picker("Size", selection: $editor.project.export.gifSize) {
            ForEach(GIFSize.allCases, id: \.self) { Text("\($0.label) (\($0.rawValue) px)") }
        }
        Picker("Frame rate", selection: $editor.project.export.gifFPS) {
            ForEach(ExportSettings.gifFrameRates, id: \.self) { Text("\($0) fps").tag($0) }
        }
        LabeledContent("Output") {
            let s = editor.project.exportSize
            Text("\(Int(s.width)) × \(Int(s.height)) · no sound").monospacedDigit()
        }
    }
}

struct PreviewQualityMenu: View {
    @AppStorage("preview.quality") private var quality = PreviewQuality.full.rawValue

    var body: some View {
        Menu {
            Picker("Preview quality", selection: $quality) {
                ForEach(PreviewQuality.allCases, id: \.self) { Text($0.label).tag($0.rawValue) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PillButtonStyle(selected: quality < 1))
        .fixedSize()
        .help("Preview quality: lower renders fewer pixels for smoother playback on slower Macs. Export is always full quality.")
    }
}

extension ExportSheet {
    static func rate(_ mbps: Double) -> String {
        mbps < 10 ? String(format: "%.1f Mbit/s", mbps) : "\(Int(mbps.rounded())) Mbit/s"
    }
}

/// Picks where the video is going, which sets the export settings for it.
struct ExportPresetMenu: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let current = ExportPreset.matching(editor.project.export)
        Menu {
            ForEach(ExportPreset.allCases.dropFirst()) { preset in
                Button {
                    withAnimation(.snappy) { preset.apply(to: &editor.project.export) }
                } label: {
                    Label { Text(preset.label) + Text("  \(preset.detail)").foregroundStyle(.secondary) } icon: {
                        Image(systemName: current == preset ? "checkmark" : preset.symbol)
                    }
                }
            }
        } label: {
            Label(current.label, systemImage: current.symbol)
        }
        .fixedSize()
        .help("Sets the resolution, frame rate, codec and file size for where the video is going")
    }
}
