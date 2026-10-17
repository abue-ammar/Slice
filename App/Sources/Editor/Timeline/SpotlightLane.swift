//
//  SpotlightLane.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import SliceCore
import SwiftUI

struct SpotlightLane: View {
    @ObservedObject var editor: EditorModel
    let pps: CGFloat
    let height: CGFloat

    static let symbol = "smallcircle.filled.circle"

    var body: some View {
        ForEach(editor.project.spotlights) { b in
            BlockView(title: "Spotlight", color: Theme.spotlight, start: b.start, end: b.end, pps: pps, height: height,
                      selected: editor.selection == .spotlight(b.id),
                      select: { editor.selection = .spotlight(b.id) },
                      setRange: { editor.setSpotlightRange(b.id, start: $0, end: $1) }) {
                HStack(spacing: 3) {
                    Image(systemName: b.followsPointer ? "cursorarrow" : Self.symbol)
                    Text(b.mode.label)
                }
            }
        }
    }
}
