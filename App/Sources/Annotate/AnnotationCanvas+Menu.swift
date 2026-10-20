//
//  AnnotationCanvas+Menu.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import AppKit
import SliceCore

extension AnnotationCanvasView {
    func toolMenu() -> NSMenu {
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        for tool in Annotation.Tool.allCases {
            let item = ActionMenuItem(title: tool.title, key: tool.key) { [weak session] in session?.tool = tool }
            item.image = NSImage(systemSymbolName: tool.symbol, accessibilityDescription: nil)
            item.state = session.tool == tool ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let names = ["Red", "Yellow", "Green", "Blue", "White", "Black"]
        for (i, color) in AnnotationSession.colors.enumerated() {
            let item = ActionMenuItem(title: names[safe: i] ?? "Colour") { [weak session] in session?.colorIndex = i }
            item.image = Self.dot(color)
            item.state = session.colorIndex == i ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        for (i, name) in ["Thin", "Medium", "Thick"].enumerated() where i < AnnotationSession.widths.count {
            let item = ActionMenuItem(title: name) { [weak session] in session?.widthIndex = i }
            item.state = session.widthIndex == i ? .on : .off
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let undo = ActionMenuItem(title: "Undo", key: "z", modifiers: .command) { [weak session] in session?.undo() }
        undo.isEnabled = session.canUndo
        let clear = ActionMenuItem(title: "Clear All", key: "\u{8}", modifiers: .command) { [weak session] in session?.clear() }
        clear.isEnabled = session.canUndo
        menu.addItem(undo)
        menu.addItem(clear)
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(title: "Stop Drawing", key: "\u{1b}") { AnnotationController.shared.toggleDrawing() })
        menu.autoenablesItems = false
        return menu
    }

    private static func dot(_ c: RGBA) -> NSImage {
        NSImage(size: NSSize(width: 12, height: 12), flipped: false) { rect in
            let path = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1).setFill()
            path.fill()
            NSColor.white.withAlphaComponent(0.3).setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }
}

/// A menu item that runs a closure; its key is shown as a reminder of the shortcut that does the same while drawing.
final class ActionMenuItem: NSMenuItem {
    private let run: () -> Void

    init(title: String, key: String = "", modifiers: NSEvent.ModifierFlags = [], run: @escaping () -> Void) {
        self.run = run
        super.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = modifiers
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError() }

    @objc private func fire() { run() }
}
