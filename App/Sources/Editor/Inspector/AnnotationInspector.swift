//
//  AnnotationInspector.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import SliceCore
import SwiftUI

struct AnnotationInspector: View {
    @ObservedObject var editor: EditorModel
    let block: AnnotationBlock
    @FocusState private var typing: Bool

    private var isText: Bool { block.mark.tool == .text }

    private func binding<T>(_ path: WritableKeyPath<AnnotationBlock, T>) -> Binding<T> {
        Binding(get: { block[keyPath: path] }, set: { v in editor.updateAnnotation(block.id) { $0[keyPath: path] = v } })
    }

    var body: some View {
        PanelSection(block.mark.tool.title) {
            if isText {
                TextField("Label", text: Binding(get: { block.mark.text ?? "" }, set: { v in
                    editor.updateAnnotation(block.id) { $0.mark.text = v }
                }), axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .lineLimit(1 ... 4)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.control))
                .focused($typing)
                // Delete and Space edit the label here, not the timeline.
                .onChange(of: typing) { _, on in editor.isEditingText = on }
                .onDisappear { if typing { editor.isEditingText = false } }
            }
            HStack(spacing: 8) {
                ForEach(AnnotationSession.colors.indices, id: \.self) { i in
                    let c = AnnotationSession.colors[i]
                    let on = c.r == block.mark.color.r && c.g == block.mark.color.g && c.b == block.mark.color.b
                    Button { editor.updateAnnotation(block.id) { $0.mark.color = RGBA(c.r, c.g, c.b, $0.mark.color.a) } } label: {
                        Circle().fill(Color(rgba: c))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
                            .frame(width: 18, height: 18)
                            .padding(3)
                            .overlay(Circle().strokeBorder(Color.white.opacity(on ? 0.9 : 0), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            PanelSlider(isText ? "Size" : "Thickness", value: binding(\.mark.width), in: 1 ... 20,
                        default: AnnotationSession.widths[1]) { "\(Int($0.rounded())) pt" }
            PanelSlider("Opacity", value: binding(\.mark.color.a), in: 0.1 ... 1, default: 1) { "\(Int(($0 * 100).rounded()))%" }
        }
        PanelDivider()
        PanelSection("Timing") {
            InfoRow(title: "Shows", value: "\(format(block.start)) – \(format(block.end))")
            if !isText, block.mark.points.count > 1 {
                PanelToggle("Draw it in as it was drawn", isOn: binding(\.drawsIn))
            }
            PanelNote("Drag it in the preview to move it, its corners to resize. Drag its edges on the timeline to change when it shows.")
        }
        Button("Delete drawing") { editor.deleteSelection() }
            .buttonStyle(DestructiveButtonStyle())
            .help("Delete key. ⌘Z undoes. The recording itself is never changed.")
    }
}
