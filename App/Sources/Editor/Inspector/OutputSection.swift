//
//  OutputSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/9/26.
//

import SliceCore
import SwiftUI

struct OutputSection: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        let export = editor.project.export
        let size = editor.project.renderSize
        let mbps = Double(export.bitRate(for: size)) / 1_000_000
        PanelSection("Video") {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(Int(size.width)) × \(Int(size.height))")
                    .font(.rounded(20, .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                Text("\(export.fps) fps · \(export.hevc ? "HEVC" : "H.264") · \(Int(mbps.rounded())) Mbit/s")
                    .font(.rounded(12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
            .animation(.snappy, value: export)

            field("Resolution") {
                SegmentedControl(selection: $editor.project.export.resolution, options: OutputResolution.allCases, title: \.label)
            }
            field("Frame rate") {
                SegmentedControl(selection: $editor.project.export.fps, options: [30, 60, 120], title: { "\($0) fps" })
            }
            field("Quality") {
                SegmentedControl(selection: $editor.project.export.quality, options: ExportQuality.allCases, title: \.label)
            }
            MoreOptions(id: "output") {
                field("Codec") {
                    SegmentedControl(selection: $editor.project.export.hevc, options: [true, false],
                                     title: { $0 ? "HEVC" : "H.264" })
                }
                PanelNote(export.hevc ? "HEVC makes smaller files." : "H.264 plays almost everywhere.")
            }
            if let recorded = editor.project.clips.compactMap(\.frameRate).max(), export.fps > recorded {
                PanelNote("Recorded at \(recorded) fps; a higher export rate repeats frames but keeps the pointer and zooms smooth.")
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            content()
        }
    }
}
