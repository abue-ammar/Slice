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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Export").font(.title2.weight(.semibold))
            Form {
                Picker("Aspect ratio", selection: $editor.project.export.aspect) {
                    ForEach(OutputAspect.allCases, id: \.self) { Text($0.menuTitle) }
                }
                OutputSettingsFields(editor: editor)
                if !editor.captions.isEmpty {
                    Toggle("Burn in subtitles", isOn: $editor.project.subtitles.burnIn)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Export…") { chooseAndExport() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func chooseAndExport() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        let size = editor.project.renderSize
        panel.nameFieldStringValue = "\(editor.project.name) \(Int(size.width))x\(Int(size.height)).mp4"
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
            let mbps = Double(editor.project.export.bitRate(for: s)) / 1_000_000
            Text("\(Int(s.width)) × \(Int(s.height)) · \(Int(mbps.rounded())) Mbit/s").monospacedDigit()
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
