//
//  DrawShortcut.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import AppKit
import Carbon.HIToolbox

/// The shortcut that turns drawing on and off, as the user set it in Settings; ⌥A until they do.
struct DrawShortcut: Codable, Equatable {
    var keyCode: Int
    var modifiers: UInt
    /// The key as typed, for showing it (A, 1, F5…).
    var key: String

    static let standard = DrawShortcut(keyCode: kVK_ANSI_A, modifiers: NSEvent.ModifierFlags.option.rawValue, key: "A")
    private static let defaultsKey = "shortcut.draw"

    static var saved: DrawShortcut {
        UserDefaults.standard.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(DrawShortcut.self, from: $0) } ?? .standard
    }

    func save() {
        if self == .standard {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }
    var combo: HotKeys.Combo { HotKeys.Combo(keyCode: keyCode, modifiers: flags) }

    var keys: [String] {
        var out: [String] = []
        if flags.contains(.control) { out.append("⌃") }
        if flags.contains(.option) { out.append("⌥") }
        if flags.contains(.shift) { out.append("⇧") }
        if flags.contains(.command) { out.append("⌘") }
        return out + [key]
    }

    /// A key press as a shortcut, if it can be one: it needs ⌘, ⌥ or ⌃, so typing never sets it off.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        self.init(keyCode: Int(event.keyCode), modifiers: flags.rawValue, key: Self.name(of: event))
    }

    init(keyCode: Int, modifiers: UInt, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    private static func name(of event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "esc"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case let code where functionKeys.contains(code): return "F\((functionKeys.firstIndex(of: code) ?? 0) + 1)"
        default:
            // The key's own letter, not what ⌥ turns it into (⌥A types å).
            return (event.charactersIgnoringModifiers ?? "?").uppercased()
        }
    }

    private static let functionKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11,
                                       kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20]
}
