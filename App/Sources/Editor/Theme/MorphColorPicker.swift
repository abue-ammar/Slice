//
//  MorphColorPicker.swift
//  Slice
//
//  Created by rit3zh CX on 10/18/26.
//

import SliceCore
import SwiftUI

/// Colour fields whose swatch grows into a full picker in place: saturation and brightness on the area, hue on the
/// slider, or a typed value in hex, RGB, HSL or OKLCH, with the numbers rolling between formats. Picking from the
/// screen and saved colours are there too. Escape or the tick closes it back into its swatch.
struct MorphColorPicker: View {
    struct Field: Identifiable {
        let id: String
        let label: String
        let color: Binding<RGBA>
    }

    let fields: [Field]
    var changed: () -> Void = {}
    @State private var editing: String?
    @Namespace private var space

    static let open = Animation.spring(duration: 0.44, bounce: 0.1)
    static let close = Animation.spring(duration: 0.3, bounce: 0)

    var body: some View {
        ZStack(alignment: .top) {
            if let field = fields.first(where: { $0.id == editing }) {
                ColorPanel(field: field, space: space, changed: changed) {
                    withAnimation(Self.close) { editing = nil }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(fields.enumerated()), id: \.element.id) { i, field in
                        if i > 0 {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        ColorTrigger(field: field, space: space) {
                            withAnimation(Self.open) { editing = field.id }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Swatch

private struct ColorTrigger: View {
    let field: MorphColorPicker.Field
    let space: Namespace.ID
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        let color = field.color.wrappedValue
        Button(action: open) {
            HStack(spacing: 8) {
                ColorChip(color: color)
                    .matchedGeometryEffect(id: "chip.\(field.id)", in: space)
                VStack(alignment: .leading, spacing: 0) {
                    Text(field.label)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .matchedGeometryEffect(id: "label.\(field.id)", in: space)
                    HexText(color: color)
                        .matchedGeometryEffect(id: "hex.\(field.id)", in: space)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(hovering ? Theme.controlHover : Theme.control)
                    .matchedGeometryEffect(id: "surface.\(field.id)", in: space)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .help("Edit the \(field.label.lowercased()) colour")
    }
}

/// The hex under a swatch's name; its characters roll when the colour changes.
struct HexText: View {
    let color: RGBA

    var body: some View {
        let hex = HSVA(color).hex
        Text(hex)
            .font(.rounded(12).monospacedDigit())
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.28), value: hex)
    }
}

struct ColorChip: View {
    let color: RGBA
    var size: CGFloat = 20

    var body: some View {
        Circle()
            .fill(Color(rgba: color))
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
    }
}

extension Color {
    init(rgba c: RGBA) { self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a) }
}
