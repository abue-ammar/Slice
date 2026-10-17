//
//  SpotlightInspector.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import SliceCore
import SwiftUI

struct SpotlightInspector: View {
    @ObservedObject var editor: EditorModel
    let block: SpotlightBlock

    private func binding<Value>(_ path: WritableKeyPath<SpotlightBlock, Value>) -> Binding<Value> {
        Binding(get: { block[keyPath: path] }, set: { v in editor.updateSpotlight(block.id) { $0[keyPath: path] = v } })
    }

    var body: some View {
        let d = SpotlightBlock(start: 0, end: 0)
        PanelSection("Spotlight") {
            SegmentedControl(selection: binding(\.mode), options: SpotlightMode.allCases, title: \.label, symbol: { $0.symbol })
            PanelSlider("Size", value: binding(\.size), in: SpotlightOverlay.sizes, default: d.size) {
                String(format: "%.1f×", $0)
            }
            PanelSlider(block.mode == .dim ? "Dim" : "Blur", value: binding(\.strength), in: 0.1 ... 1, default: d.strength) {
                "\(Int(($0 * 100).rounded()))%"
            }
            PanelToggle("Follow the pointer", isOn: binding(\.followsPointer))
            PanelNote(block.followsPointer
                ? "The circle stays on the pointer as it moves. Drag the block's edges on the timeline to change how long."
                : "Drag the circle in the preview onto what to light, and its edge to resize. It stays put through zooms.")
        }
        PanelDivider()
        PanelSection("On every click") {
            PanelToggle("Spotlight each click", isOn: $editor.project.cursor.spotlight.enabled)
            PanelNote("Lights up each click on its own, styled in Cursor › Clicks. This spotlight takes over while it shows.")
        }
        Button("Delete spotlight") { editor.deleteSelection() }
            .buttonStyle(DestructiveButtonStyle())
            .help("Delete key. ⌘Z undoes.")
    }
}
