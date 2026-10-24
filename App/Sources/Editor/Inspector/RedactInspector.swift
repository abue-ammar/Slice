//
//  RedactInspector.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import SliceCore
import SwiftUI

struct RedactInspector: View {
    @ObservedObject var editor: EditorModel
    let block: RedactBlock

    var body: some View {
        PanelSection("Hide with") {
            SegmentedControl(selection: Binding(get: { block.style }, set: { s in editor.updateRedaction(block.id) { $0.style = s } }),
                             options: RedactStyle.allCases, title: \.label,
                             symbol: { $0 == .blur ? "drop.halffull" : "squareshape.split.3x3" })
            PanelSlider("Strength", value: Binding(get: { block.strength }, set: { v in editor.updateRedaction(block.id) { $0.strength = v } }),
                        in: 0 ... 1, default: RedactBlock(start: 0, end: 0).strength) { "\(Int(($0 * 100).rounded()))%" }
            PanelNote(block.isAuto
                ? "Found \(block.label?.lowercased() ?? "sensitive text") here. Drag the box in the preview if it's off, or its edges on the timeline to change how long it shows."
                : "Drag the box in the preview to cover what to hide; drag its corners to resize. It stays put through zooms.")
        }
        PanelDivider()
        PanelSection("Find automatically") {
            SensitiveTextButton(editor: editor, wide: true)
            PanelNote("Blurs emails, card numbers and API keys wherever they show. Scanning again replaces the Auto blurs and keeps yours.")
        }
        Button("Delete blur") { editor.deleteSelection() }
            .buttonStyle(DestructiveButtonStyle())
            .help("Delete key. ⌘Z undoes.")
    }
}

struct SectionSpeedPicker: View {
    @ObservedObject var editor: EditorModel
    let segment: Segment

    var body: some View {
        PanelSection("Speed") {
            SegmentedControl(selection: Binding(get: { SpeedRange.choices.min { abs($0 - segment.speed) < abs($1 - segment.speed) } ?? 1 },
                                                set: { editor.setSpeed($0, for: segment) }),
                             options: SpeedRange.choices, title: SpeedRange.label)
            PanelNote(note)
        }
    }

    private var note: String {
        if segment.isSlowed { return "Plays at \(SpeedRange.label(segment.speed)) speed, without sound. Good for a quick move worth a closer look." }
        if segment.isSpedUp { return "Plays \(SpeedRange.label(segment.speed)) as fast, without sound. Good for waiting, loading and long typing." }
        return "Speed up waiting or typing, or slow down a quick move. Any speed but 1× plays without sound."
    }
}
