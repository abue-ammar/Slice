//
//  ColorPanel.swift
//  Slice
//
//  Created by rit3zh CX on 10/18/26.
//

import AppKit
import SliceCore
import SwiftUI

/// The open picker. Its surface, swatch, name and hex are the swatch's own, grown into place; the controls fade in
/// behind them once the surface has room.
struct ColorPanel: View {
    let field: MorphColorPicker.Field
    let space: Namespace.ID
    let changed: () -> Void
    let close: () -> Void

    @State private var hsva: HSVA
    @State private var shown = false
    @State private var dragging: Part?
    @State private var draft = ""
    @State private var invalid = false
    @State private var shakes = 0
    @FocusState private var typing: Bool
    @AppStorage("colorPicker.format") private var formatName = ColorFormat.hex.rawValue
    @AppStorage("colorPicker.saved") private var savedList = ""

    private enum Part { case area, hue }

    /// A click lands with a soft settle; under a drag the thumb stays on the pointer.
    private static let thumbSpring = Animation.spring(duration: 0.26, bounce: 0.15)
    private static let knob: CGFloat = 18
    private static let savedLimit = 8

    init(field: MorphColorPicker.Field, space: Namespace.ID, changed: @escaping () -> Void, close: @escaping () -> Void) {
        self.field = field
        self.space = space
        self.changed = changed
        self.close = close
        _hsva = State(initialValue: HSVA(field.color.wrappedValue))
    }

    private var format: ColorFormat { ColorFormat(rawValue: formatName) ?? .hex }
    private var saved: [String] { savedList.split(separator: ",").map(String.init) }
    private var thumbAnimation: Animation? { dragging == nil ? Self.thumbSpring : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            head
            VStack(alignment: .leading, spacing: 12) {
                area
                hueSlider
                valueField
                swatches
            }
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : -8)
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.control)
                .matchedGeometryEffect(id: "surface.\(field.id)", in: space)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.24).delay(0.12)) { shown = true } }
        .onChange(of: field.color.wrappedValue) { _, new in
            if HSVA(new).hex != hsva.hex { withAnimation(Self.thumbSpring) { hsva = HSVA(new, hue: hsva.h) } }
        }
        .onExitCommand(perform: close)
    }

    private func commit(_ next: HSVA) {
        hsva = next
        let rgba = next.rgba
        guard rgba != field.color.wrappedValue else { return }
        field.color.wrappedValue = rgba
        changed()
    }

    // MARK: Head

    private var head: some View {
        HStack(spacing: 8) {
            ColorChip(color: hsva.rgba)
                .matchedGeometryEffect(id: "chip.\(field.id)", in: space)
            VStack(alignment: .leading, spacing: 0) {
                Text(field.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .matchedGeometryEffect(id: "label.\(field.id)", in: space)
                HexText(color: hsva.rgba)
                    .matchedGeometryEffect(id: "hex.\(field.id)", in: space)
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Button(action: sample) { Image(systemName: "eyedropper") }
                    .help("Pick a colour from anywhere on screen")
                Button(action: close) { Image(systemName: "checkmark") }
                    .help("Done")
            }
            .buttonStyle(IconButtonStyle(size: 26, iconSize: 12))
            .opacity(shown ? 1 : 0)
        }
        .padding(.leading, -2)
    }

    private func sample() {
        NSColorSampler().show { picked in
            guard let rgb = picked?.usingColorSpace(.sRGB) else { return }
            let next = HSVA(RGBA(rgb.redComponent, rgb.greenComponent, rgb.blueComponent), hue: hsva.h)
            withAnimation(Self.thumbSpring) { commit(next) }
        }
    }

    // MARK: Area

    private var area: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack(alignment: .topLeading) {
                ZStack {
                    Color(rgba: hsva.pure)
                    LinearGradient(colors: [.white, .white.opacity(0)], startPoint: .leading, endPoint: .trailing)
                    LinearGradient(colors: [.black.opacity(0), .black], startPoint: .top, endPoint: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke))
                Thumb(fill: Color(rgba: hsva.rgba), active: dragging == .area)
                    .position(x: hsva.s * size.width, y: (1 - hsva.v) * size.height)
                    .animation(thumbAnimation, value: hsva)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if dragging == nil {
                        withAnimation(Self.thumbSpring) { dragging = .area; pick(drag.location, in: size) }
                    } else {
                        pick(drag.location, in: size)
                    }
                }
                .onEnded { _ in dragging = nil })
        }
        .frame(height: 148)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
            let step = press.modifiers.contains(.shift) ? 0.1 : 0.01
            var next = hsva
            switch press.key {
            case .leftArrow: next.s = max(next.s - step, 0)
            case .rightArrow: next.s = min(next.s + step, 1)
            case .upArrow: next.v = min(next.v + step, 1)
            default: next.v = max(next.v - step, 0)
            }
            withAnimation(Self.thumbSpring) { commit(next) }
            return .handled
        }
        .help("Drag to choose how vivid and how bright. Arrow keys nudge it.")
    }

    private func pick(_ p: CGPoint, in size: CGSize) {
        var next = hsva
        next.s = min(max(p.x / max(size.width, 1), 0), 1)
        next.v = 1 - min(max(p.y / max(size.height, 1), 0), 1)
        commit(next)
    }

    // MARK: Hue

    private var hueSlider: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - Self.knob, 1)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: stride(from: 0.0, through: 360, by: 30).map { Color(rgba: HSVA(h: $0, s: 1, v: 1).rgba) },
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                    .overlay(Capsule().strokeBorder(Theme.stroke))
                Thumb(fill: Color(rgba: hsva.pure), active: dragging == .hue)
                    .position(x: Self.knob / 2 + travel * hsva.h / 360, y: geo.size.height / 2)
                    .animation(thumbAnimation, value: hsva)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    let h = min(max((drag.location.x - Self.knob / 2) / travel, 0), 1) * 359.9
                    if dragging == nil {
                        withAnimation(Self.thumbSpring) { dragging = .hue; commit(HSVA(h: h, s: hsva.s, v: hsva.v, a: hsva.a)) }
                    } else {
                        commit(HSVA(h: h, s: hsva.s, v: hsva.v, a: hsva.a))
                    }
                }
                .onEnded { _ in dragging = nil })
        }
        .frame(height: Self.knob)
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(keys: [.leftArrow, .rightArrow]) { press in
            let step = press.modifiers.contains(.shift) ? 10.0 : 1
            var next = hsva
            next.h = min(max(next.h + (press.key == .leftArrow ? -step : step), 0), 359.9)
            withAnimation(Self.thumbSpring) { commit(next) }
            return .handled
        }
        .help("Hue. Arrow keys nudge it.")
    }
}

// MARK: - Value and saved colours

private extension ColorPanel {
    var valueField: some View {
        HStack(spacing: 6) {
            Button {
                typing = false
                withAnimation(.snappy(duration: 0.32)) { formatName = format.next.rawValue }
            } label: {
                Text(format.name)
                    .font(.system(size: 11, weight: .semibold))
                    .contentTransition(.interpolate)
                    .frame(width: 50, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.control))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Switch between hex, RGB, HSL and OKLCH")

            valueInput
        }
    }

    var fieldHelp: String {
        invalid ? "Type a hex like #2F6BFF, or the numbers for \(format.name)" : "Type a colour in \(format.name)"
    }

    var valueInput: some View {
        let stroke = invalid ? Color.red.opacity(0.75) : typing ? Theme.accent.opacity(0.75) : Theme.stroke
        return ZStack(alignment: .leading) {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($typing)
                    .opacity(typing ? 1 : 0.001)
                    .onSubmit { submit() }
                if !typing {
                    Text(hsva.text(format))
                        .contentTransition(.numericText())
                        .animation(dragging == nil ? .snappy(duration: 0.3) : nil, value: hsva.text(format))
                        .allowsHitTesting(false)
                }
            }
            .font(.rounded(12.5).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, 9)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.black.opacity(0.22)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(stroke))
            .modifier(Shake(trigger: shakes))
            .animation(Theme.hover, value: typing)
            .animation(Theme.hover, value: invalid)
            .onChange(of: typing) { _, now in
                if now {
                    draft = hsva.text(format)
                } else if !submit() {
                    invalid = false
                }
            }
            .onChange(of: draft) { invalid = false }
            .help(fieldHelp)
    }

    @discardableResult
    func submit() -> Bool {
        // Shown values are rounded; reading one back unchanged would nudge the colour.
        guard draft.trimmingCharacters(in: .whitespaces) != hsva.text(format) else { return true }
        guard let next = HSVA.parse(draft, as: format, hue: hsva.h) else {
            invalid = true
            shakes += 1
            return false
        }
        withAnimation(Self.thumbSpring) { commit(next) }
        draft = next.text(format)
        return true
    }

    var swatches: some View {
        HStack(spacing: 7) {
            Button(action: save) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().strokeBorder(Color.white.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Save this colour for later")
            ForEach(saved, id: \.self) { hex in
                if let color = HSVA.parse(hex, as: .hex, hue: 0) {
                    Button {
                        withAnimation(Self.thumbSpring) { commit(HSVA(color.rgba, hue: hsva.h)) }
                    } label: {
                        ColorChip(color: color.rgba, size: 22)
                            .padding(2)
                            .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 1.5).opacity(hex == hsva.hex ? 1 : 0))
                    }
                    .buttonStyle(.plain)
                    .help(hex)
                    .contextMenu { Button("Remove") { remove(hex) } }
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
                }
            }
            Spacer(minLength: 0)
        }
        .animation(.snappy(duration: 0.3), value: savedList)
    }

    func save() {
        let hex = hsva.hex
        savedList = ([hex] + saved.filter { $0 != hex }).prefix(Self.savedLimit).joined(separator: ",")
    }

    func remove(_ hex: String) {
        savedList = saved.filter { $0 != hex }.joined(separator: ",")
    }
}

private struct Thumb: View {
    let fill: Color
    var active = false

    var body: some View {
        Circle()
            .fill(fill)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Color.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .scaleEffect(active ? 1.15 : 1)
            .allowsHitTesting(false)
    }
}

/// A short no-shake for a value that couldn't be read.
private struct Shake: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        content.keyframeAnimator(initialValue: 0.0, trigger: trigger) { view, x in
            view.offset(x: x)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(-5, duration: 0.07)
                CubicKeyframe(4, duration: 0.08)
                CubicKeyframe(-2, duration: 0.08)
                CubicKeyframe(0, duration: 0.09)
            }
        }
    }
}
