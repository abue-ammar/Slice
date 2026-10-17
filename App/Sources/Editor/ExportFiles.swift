//
//  ExportFiles.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The exported files, each one ready to drag straight into another app.
struct ExportFiles: View {
    let urls: [URL]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(urls, id: \.self) { ExportFileChip(url: $0) }
        }
    }

    static func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }
}

private struct ExportFileChip: View {
    let url: URL
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let bytes = ExportFiles.size(of: url) {
                    Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))
                        .font(.rounded(11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: 220)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Theme.controlHover : Theme.control))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        .help("Drag into another app to share it. Double-click to play.")
    }
}
