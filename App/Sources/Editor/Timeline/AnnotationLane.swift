//
//  AnnotationLane.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import SliceCore
import SwiftUI

/// What was drawn while recording, one block per mark, from when it was drawn to when it was cleared. Marks on
/// screen together share the lane in rows.
struct AnnotationLane: View {
    @ObservedObject var editor: EditorModel
    let pps: CGFloat
    let height: CGFloat

    static let symbol = "pencil.and.scribble"
    static let maxRows = 3

    var body: some View {
        let blocks = editor.project.annotations.sorted { $0.start < $1.start }
        let rows = Self.rows(for: blocks)
        let count = min((rows.values.max() ?? 0) + 1, Self.maxRows)
        let gap: CGFloat = 2
        let rowHeight = (height - gap * CGFloat(count - 1)) / CGFloat(count)
        ZStack(alignment: .topLeading) {
            ForEach(blocks) { b in
                let row = min(rows[b.id] ?? 0, count - 1)
                BlockView(title: b.mark.tool.title, color: Theme.annotation, start: b.start, end: b.end, pps: pps,
                          height: rowHeight, selected: editor.selection == .annotation(b.id),
                          select: { editor.selection = .annotation(b.id) },
                          setRange: { editor.setAnnotationRange(b.id, start: $0, end: $1) },
                          compact: count > 1) {
                    HStack(spacing: 4) {
                        Circle().fill(Color(rgba: b.mark.color)).frame(width: 7, height: 7)
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
                        Image(systemName: b.mark.tool.symbol)
                        Text(b.mark.tool == .text ? b.mark.text ?? "Text" : b.mark.tool.title)
                    }
                }
                .offset(y: CGFloat(row) * (rowHeight + gap))
            }
        }
    }

    /// Puts each block on the first row that's free when it starts.
    static func rows(for sorted: [AnnotationBlock]) -> [UUID: Int] {
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
