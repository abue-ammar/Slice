//
//  Keystrokes.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/2/26.
//

import Foundation

public struct KeystrokeSettings: Codable, Equatable {
    public enum Position: String, Codable, CaseIterable { case bottom, top }

    public var visible = true
    public var singleKeys = false
    public var position: Position = .bottom
    public var size = 0.04
    public var hold = 1.4
    public var sound: KeyboardSound = .none
    public var soundVolume = 0.5

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = KeystrokeSettings()
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? d.visible
        singleKeys = try c.decodeIfPresent(Bool.self, forKey: .singleKeys) ?? d.singleKeys
        position = (try? c.decodeIfPresent(Position.self, forKey: .position)) ?? d.position
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        hold = try c.decodeIfPresent(Double.self, forKey: .hold) ?? d.hold
        sound = (try? c.decodeIfPresent(KeyboardSound.self, forKey: .sound)) ?? d.sound
        soundVolume = try c.decodeIfPresent(Double.self, forKey: .soundVolume) ?? d.soundVolume
    }
}

public struct KeyHit: Codable, Equatable {
    /// Raw values are saved in takes and name the pack's own recordings, so never rename them.
    public enum Kind: String, Codable { case key, space, enter, backspace, modifier }

    public var t: Double
    public var kind: Kind

    public init(t: Double, kind: Kind) {
        self.t = t
        self.kind = kind
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        t = try c.decode(Double.self, forKey: .t)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .key
    }

    public static func kind(keyCode: UInt16) -> Kind {
        switch keyCode {
        case 49: .space
        case 36, 76: .enter
        case 51, 117: .backspace
        case 54 ... 63: .modifier
        default: .key
        }
    }

    static func kind(named key: String) -> Kind {
        switch key {
        case "Space": .space
        case "↩", "⌅": .enter
        case "⌫", "⌦": .backspace
        default: .key
        }
    }
}

/// The keyboard heard as keys are pressed. Raw values are saved in projects, so never rename them.
public enum KeyboardSound: String, Codable, CaseIterable {
    case none
    case cherryBlue
    case apexPro
    case holyPanda

    public var label: String {
        switch self {
        case .none: "None"
        case .cherryBlue: "Cherry MX Blue"
        case .apexPro: "Apex Pro"
        case .holyPanda: "Holy Panda"
        }
    }

    public var detail: String {
        switch self {
        case .none: "Silent typing"
        case .cherryBlue: "Clicky"
        case .apexPro: "Smooth"
        case .holyPanda: "Deep"
        }
    }

    private var folder: String? {
        switch self {
        case .none: nil
        case .cherryBlue: "cherry-mx-blue"
        case .apexPro: "apex-pro"
        case .holyPanda: "holy-panda"
        }
    }

    public var files: [URL] {
        guard let folder else { return [] }
        return (Bundle.module.urls(forResourcesWithExtension: "wav", subdirectory: "Sounds/Keyboards/\(folder)") ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func picks(for kinds: [KeyHit.Kind]) -> [Int] {
        let names = files.map { $0.deletingPathExtension().lastPathComponent }
        let keys = names.indices.filter { names[$0].hasPrefix("key") }
        guard !keys.isEmpty else { return [] }
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        var last = 0
        return kinds.map { kind in
            if kind != .key, kind != .modifier, let own = names.firstIndex(of: kind.rawValue) { return own }
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            last = (last + 1 + Int((seed >> 33) % UInt64(max(keys.count - 1, 1)))) % keys.count
            return keys[last]
        }
    }
}

public struct KeyPress: Codable, Equatable {
    public var t: Double
    public var modifiers: String
    public var key: String

    public init(t: Double, modifiers: String, key: String) {
        self.t = t
        self.modifiers = modifiers
        self.key = key
    }

    public var isShortcut: Bool { modifiers.contains { "⌘⌃⌥".contains($0) } }

    public var label: String { modifiers.isEmpty ? key : "\(modifiers) \(key)" }

    public static func make(t: Double, keyCode: UInt16, characters: String?,
                            control: Bool, option: Bool, shift: Bool, command: Bool) -> KeyPress? {
        let modifiers = (control ? "⌃" : "") + (option ? "⌥" : "") + (shift ? "⇧" : "") + (command ? "⌘" : "")
        let shortcut = control || option || command
        if let named = namedKeys[keyCode] {
            if keyCode == 49, !shortcut { return nil }
            return KeyPress(t: t, modifiers: modifiers, key: named)
        }
        guard shortcut, let c = characters?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), !c.isEmpty,
              c.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return KeyPress(t: t, modifiers: modifiers, key: c)
    }

    static let namedKeys: [UInt16: String] = [
        36: "↩", 76: "⌅", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦", 53: "esc",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
        90: "F20",
    ]
}

public struct KeystrokeState: Equatable {
    public var label: String
    public var count: Int
    public var opacity: Double
    public var blur: Double
    public var scale: Double
    public var drop: Double
}

public struct KeystrokeTimeline {
    struct Group {
        var label: String
        var presses: [Double]
        var inStart: Double
        var outStart = 0.0
        var outDuration = 0.0
    }

    private(set) var groups: [Group] = []

    static let inDuration = 0.32
    static let outDuration = 0.28
    static let swapOut = 0.12
    static let swapDelay = 0.05
    static let pulse = 0.2

    public init(presses: [KeyPress], settings: KeystrokeSettings) {
        guard settings.visible else { return }
        let hold = max(settings.hold, 0.2)
        for p in presses.sorted(by: { $0.t < $1.t }) where p.isShortcut || settings.singleKeys {
            let label = p.label
            if let last = groups.last, last.label == label, let prev = last.presses.last, p.t - prev <= hold {
                groups[groups.count - 1].presses.append(p.t)
            } else {
                groups.append(Group(label: label, presses: [p.t], inStart: p.t))
            }
        }
        for i in groups.indices {
            let natural = groups[i].presses.last! + hold
            guard i + 1 < groups.count else {
                groups[i].outStart = natural
                groups[i].outDuration = Self.outDuration
                continue
            }
            let next = groups[i + 1].presses[0]
            if next < natural + Self.outDuration {
                let end = min(natural + Self.outDuration, next + Self.swapOut)
                groups[i].outStart = min(natural, next)
                groups[i].outDuration = max(end - groups[i].outStart, 0.01)
                groups[i + 1].inStart = next + Self.swapDelay
            } else {
                groups[i].outStart = natural
                groups[i].outDuration = Self.outDuration
            }
        }
    }

    public var isEmpty: Bool { groups.isEmpty }

    public func states(at t: Double) -> [KeystrokeState] {
        guard let i = groups.lastIndex(where: { $0.presses[0] <= t }) else { return [] }
        return [i - 2, i - 1, i].compactMap { $0 >= 0 ? state(groups[$0], at: t) : nil }
    }

    private func state(_ g: Group, at t: Double) -> KeystrokeState? {
        guard t >= g.inStart, t < g.outStart + g.outDuration else { return nil }
        let a = min((t - g.inStart) / Self.inDuration, 1)
        let o = min(max((t - g.outStart) / g.outDuration, 0), 1)
        let settle = 1 - pow(1 - a, 3)
        let shown = 1 - pow(1 - min(a / 0.6, 1), 2)
        let blurOut = 1 - pow(1 - o, 2)
        var blur = max(1 - settle, blurOut)
        var scale = (0.92 + 0.08 * settle) * (1 - 0.06 * o * o)
        var count = 1
        for (k, p) in g.presses.enumerated().dropFirst() where t >= p {
            let b = (t - p) / Self.pulse
            if b >= 0.5 { count = k + 1 }
            if b < 1 {
                let bump = sin(.pi * b)
                blur = max(blur, 0.4 * bump)
                scale *= 1 - 0.05 * bump
            }
        }
        return KeystrokeState(label: g.label, count: count, opacity: shown * (1 - o * o * (3 - 2 * o)), blur: blur,
                              scale: scale, drop: 0.18 * (1 - settle))
    }
}
