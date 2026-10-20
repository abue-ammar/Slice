//
//  AnnotationLabelEditor.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import AppKit
import SliceCore

extension AnnotationCanvasView {
    func beginLabel(at point: CGPoint) {
        guard let panel = window as? AnnotationCanvasPanel else { return }
        let editor = AnnotationLabelEditor(view: self, anchor: point)
        label = editor
        session.isTyping = true
        panel.keyable = true
        panel.makeKey()
        editor.start()
    }

    func endLabel(_ editor: AnnotationLabelEditor) {
        guard label === editor else { return }
        label = nil
        session.isTyping = false
        guard let panel = window as? AnnotationCanvasPanel else { return }
        panel.keyable = false
        // Ordering the panel out and back hands the keyboard back to the app being recorded, which stays in front.
        if panel.isKeyWindow {
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
    }
}

/// Types a label where the text tool clicked: Return keeps it, ⌥Return starts a new line, Esc drops it. It appears
/// in the video once it's kept, in the same place and size as here.
@MainActor
final class AnnotationLabelEditor: NSObject, NSTextFieldDelegate {
    private weak var view: AnnotationCanvasView?
    private let anchor: CGPoint
    private let field = NSTextField()
    private var ended = false

    init(view: AnnotationCanvasView, anchor: CGPoint) {
        self.view = view
        self.anchor = anchor
    }

    func start() {
        guard let view else { return }
        let session = view.session
        let sample = Annotation(tool: .text, color: session.color, width: session.width)
        let color = NSColor(srgbRed: session.color.r, green: session.color.g, blue: session.color.b, alpha: 1)
        field.font = AnnotationPainter.labelFont(sample, scale: 1)
        field.textColor = color
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.usesSingleLineMode = false
        field.cell?.wraps = false
        // Scrolls rather than stopping the typing if the text ever outruns the field before it grows.
        field.cell?.isScrollable = true
        field.placeholderAttributedString = NSAttributedString(string: "Label", attributes: [
            .font: field.font as Any, .foregroundColor: color.withAlphaComponent(0.4),
        ])
        field.delegate = self
        view.addSubview(field)
        fit()
        view.window?.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertionPointColor = color
    }

    func commit() { end(keep: true) }

    private func end(keep: Bool) {
        guard !ended, let view else { return }
        ended = true
        if keep { view.session.addLabel(field.stringValue, at: anchor, time: AnnotationSession.now) }
        field.delegate = nil
        field.removeFromSuperview()
        view.endLabel(self)
    }

    /// Grows with the text as it's typed, line by line, its top-left on the click as the drawn label's is. Measured
    /// from the text being edited: the field's own size-to-fit only sees the text it had before editing began.
    private func fit() {
        guard let view, let font = field.font else { return }
        let text = field.currentEditor()?.string ?? field.stringValue
        let lines = (text.isEmpty ? "Label" : text).components(separatedBy: "\n")
        let width = lines.map { ($0 as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let height = CGFloat(lines.count) * AnnotationPainter.lineHeight(font) + 4
        let o = view.origin
        // A text field's cell insets its text by 2 points; the extra width keeps the next letter from scrolling it.
        field.frame = CGRect(x: anchor.x - o.x - 2, y: anchor.y - o.y - height, width: ceil(width) + font.pointSize + 12, height: height)
    }

    func controlTextDidChange(_ obj: Notification) { fit() }

    func controlTextDidEndEditing(_ obj: Notification) { end(keep: true) }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            end(keep: true)
        case #selector(NSResponder.cancelOperation(_:)):
            end(keep: false)
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            textView.insertText("\n", replacementRange: textView.selectedRange())
            fit()
        default:
            return false
        }
        return true
    }
}
