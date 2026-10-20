//
//  EditorTheme.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import SliceCore
import SwiftUI

enum Theme {
    static let window = Color(red: 0.047, green: 0.047, blue: 0.055)
    static let panel = Color(red: 0.078, green: 0.078, blue: 0.09)
    static let control = Color.white.opacity(0.055)
    static let controlHover = Color.white.opacity(0.09)
    static let thumb = Color.white.opacity(0.13)
    static let stroke = Color.white.opacity(0.06)
    static let accent = Color(red: 0.4, green: 0.64, blue: 1.0)

    static let clip = Color(red: 0.88, green: 0.6, blue: 0.22)
    static let zoom = Color(red: 0.3, green: 0.55, blue: 0.96)
    static let camera = Color(red: 0.2, green: 0.64, blue: 0.62)
    static let music = Color(red: 0.56, green: 0.42, blue: 0.95)
    static let phone = Color(red: 0.95, green: 0.47, blue: 0.6)
    static let privacy = Color(red: 0.46, green: 0.52, blue: 0.64)
    static let spotlight = Color(red: 0.86, green: 0.76, blue: 0.38)
    static let annotation = Color(red: 0.93, green: 0.45, blue: 0.38)

    static let hover = Animation.smooth(duration: 0.2)
    static let press = Animation.snappy(duration: 0.14)
    static let move = Animation.spring(duration: 0.38, bounce: 0.18)
    static let slide = Animation.smooth(duration: 0.32)
    static let swap = Animation.smooth(duration: 0.3)
}

extension Font {
    static func rounded(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Buttons

struct IconButtonStyle: ButtonStyle {
    var selected = false
    var size: CGFloat = 32
    var iconSize: CGFloat = 15

    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration, selected: selected, size: size, iconSize: iconSize)
    }
}

private struct IconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let size: CGFloat
    let iconSize: CGFloat
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(size: iconSize, weight: .medium))
            .foregroundStyle(selected ? Theme.accent : hovering ? Color.primary : Color.secondary)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.15) : hovering ? Theme.controlHover : .clear))
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(isEnabled ? 1 : 0.3)
            .onHover { hovering = $0 && isEnabled }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.hover, value: selected)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

struct PillButtonStyle: ButtonStyle {
    var selected = false
    var prominent = false
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        PillButtonBody(configuration: configuration, selected: selected, prominent: prominent, fullWidth: fullWidth)
    }
}

private struct PillButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let prominent: Bool
    let fullWidth: Bool
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    private var fill: Color {
        if prominent { return Theme.accent.opacity(hovering ? 1 : 0.9) }
        if selected { return hovering ? Theme.thumb.opacity(1.2) : Theme.thumb }
        return hovering ? Theme.controlHover : Theme.control
    }

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(prominent || selected || hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 && isEnabled }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.hover, value: selected)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { DestructiveBody(configuration: configuration) }
}

private struct DestructiveBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.red.opacity(hovering ? 1 : 0.85))
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.red.opacity(hovering ? 0.16 : 0.08)))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.press, value: configuration.isPressed)
    }
}
