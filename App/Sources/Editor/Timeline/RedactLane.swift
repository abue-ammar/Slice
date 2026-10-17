//
//  RedactLane.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import SliceCore
import SwiftUI

struct RedactLaneContent: View {
    @ObservedObject var editor: EditorModel
    let pps: CGFloat
    let height: CGFloat

    static let maxRows = 3

    var body: some View {
        let blocks = editor.project.redactions.sorted { $0.start < $1.start }
        let rows = Self.rows(for: blocks)
        let count = min((rows.values.max() ?? 0) + 1, Self.maxRows)
        let gap: CGFloat = 2
        let rowHeight = (height - gap * CGFloat(count - 1)) / CGFloat(count)
        ZStack(alignment: .topLeading) {
            ForEach(blocks) { b in
                let row = min(rows[b.id] ?? 0, count - 1)
                BlockView(title: "Blur", color: Theme.privacy, start: b.start, end: b.end, pps: pps, height: rowHeight,
                          selected: editor.selection == .redact(b.id),
                          select: { editor.selection = .redact(b.id) },
                          setRange: { editor.setRedactionRange(b.id, start: $0, end: $1) },
                          compact: count > 1) {
                    HStack(spacing: 3) {
                        Image(systemName: b.style == .blur ? "drop.halffull" : "squareshape.split.3x3")
                        Text(b.label ?? b.style.label)
                        if b.isAuto, count == 1 { Text("· Auto") }
                    }
                }
                .offset(y: CGFloat(row) * (rowHeight + gap))
            }
            if editor.project.redactions.isEmpty || editor.privacyScanProgress != nil {
                SensitiveTextButton(editor: editor)
                    .padding(.leading, 6)
                    .frame(height: height)
                    .background(GeometryReader { Color.clear.preference(key: LaneReservedWidth.self, value: $0.frame(in: .local).maxX + 6) })
                    .transition(.opacity)
            }
        }
        .animation(Theme.hover, value: editor.privacyScanProgress == nil)
    }

    /// Puts each block on the first row that's free when it starts.
    static func rows(for sorted: [RedactBlock]) -> [UUID: Int] {
        var ends: [Double] = []
        var out: [UUID: Int] = [:]
        for b in sorted {
            if let free = ends.firstIndex(where: { $0 <= b.start + 1e-6 }) {
                ends[free] = b.end
                out[b.id] = free
            } else {
                ends.append(b.end)
                out[b.id] = ends.count - 1
            }
        }
        return out
    }
}

/// Starts a scan for emails, card numbers and keys, and shows how far it's got.
struct SensitiveTextButton: View {
    @ObservedObject var editor: EditorModel
    var wide = false

    var body: some View {
        Group {
            if let p = editor.privacyScanProgress {
                HStack(spacing: 7) {
                    ProgressView(value: p).progressViewStyle(.circular).controlSize(.mini)
                    Text("Finding sensitive text… \(Int((p * 100).rounded()))%")
                        .font(.system(size: 11).monospacedDigit())
                        .contentTransition(.numericText(value: p))
                    Button { editor.cancelSensitiveTextScan() } label: { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle(size: 18, iconSize: 9))
                        .help("Stop")
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .frame(maxWidth: wide ? .infinity : nil, minHeight: wide ? 34 : 24)
                .background(Capsule().fill(Theme.control))
            } else if wide {
                Button { editor.findSensitiveText() } label: { Label("Find sensitive text", systemImage: "eye.slash") }
                    .buttonStyle(WideButtonStyle())
                    .help(Self.help)
            } else {
                Button { editor.findSensitiveText() } label: { Label("Find sensitive text", systemImage: "eye.slash") }
                    .buttonStyle(PillButtonStyle())
                    .help(Self.help)
            }
        }
        .disabled(editor.project.clips.isEmpty)
    }

    static let help = "Reads the screen and blurs emails, card numbers and API keys wherever they show. Blurs it adds are marked Auto."
}
