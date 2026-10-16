//
//  PanelControls.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import SliceCore
import SwiftUI

struct PanelSection<Content: View>: View {
    let title: String
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(_ title: String, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                trailing
            }
            content
        }
    }
}

struct PanelDivider: View {
    var body: some View { Rectangle().fill(Theme.stroke).frame(height: 1).padding(.vertical, 2) }
}

struct PanelSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var defaultValue: Double?
    var format: (Double) -> String

    init(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, default defaultValue: Double? = nil,
         format: @escaping (Double) -> String) {
        self.title = title
        _value = value
        self.range = range
        self.defaultValue = defaultValue
        self.format = format
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(title).font(.system(size: 13))
                Spacer()
                if let defaultValue {
                    let changed = abs(value - defaultValue) > 0.0001
                    Button { withAnimation(Theme.move) { value = defaultValue } } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(IconButtonStyle(size: 18, iconSize: 9))
                    .opacity(changed ? 1 : 0)
                    .scaleEffect(changed ? 1 : 0.6)
                    .disabled(!changed)
                    .help("Reset to \(format(defaultValue))")
                    .animation(Theme.hover, value: changed)
                }
                Text(format(value))
                    .font(.rounded(12).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: value))
                    .animation(.snappy(duration: 0.25), value: format(value))
            }
            SmoothSlider(value: $value, in: range)
        }
    }
}

struct SmoothSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false
    @State private var dragging = false

    init(value: Binding<Double>, in range: ClosedRange<Double>) {
        _value = value
        self.range = range
    }

    private let knob: CGFloat = 14

    private var fraction: CGFloat {
        CGFloat(min(max((value - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1))
    }

    var body: some View {
        GeometryReader { geo in
            let travel = max(geo.size.width - knob, 1)
            let x = knob / 2 + travel * fraction
            let track: CGFloat = hovering || dragging ? 5 : 4
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09)).frame(height: track)
                Capsule().fill(Theme.accent.opacity(isEnabled ? 1 : 0.5)).frame(width: x, height: track)
                Circle()
                    .fill(Color.white)
                    .frame(width: knob, height: knob)
                    .shadow(color: .black.opacity(0.35), radius: dragging ? 4 : 2, y: 1)
                    .scaleEffect(dragging ? 1.18 : hovering ? 1.07 : 1)
                    .offset(x: x - knob / 2)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    guard isEnabled else { return }
                    if !dragging { dragging = true }
                    let f = min(max((v.location.x - knob / 2) / travel, 0), 1)
                    value = range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)
                }
                .onEnded { _ in dragging = false })
        }
        .frame(height: 18)
        .onHover { hovering = $0 && isEnabled }
        .animation(Theme.hover, value: hovering)
        .animation(Theme.press, value: dragging)
        .accessibilityElement()
        .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

struct SegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let title: (Value) -> String
    var symbol: (Value) -> String? = { _ in nil }
    @Namespace private var namespace
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                SegmentButton(title: title(option), symbol: symbol(option), selected: option == selection, namespace: namespace) {
                    withAnimation(Theme.slide) { selection = option }
                }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
        .opacity(isEnabled ? 1 : 0.4)
    }
}

private struct SegmentButton: View {
    let title: String
    let symbol: String?
    let selected: Bool
    let namespace: Namespace.ID
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.system(size: 11, weight: .medium)) }
                Text(title)
            }
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(selected ? Color.white : hovering ? Color.primary : Color.secondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Theme.accent)
                        .shadow(color: Theme.accent.opacity(0.3), radius: 4, y: 1)
                        .matchedGeometryEffect(id: "thumb", in: namespace)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
    }
}

struct PanelToggle: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            Toggle(title, isOn: $isOn.animation(.snappy))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .tint(Theme.accent)
        }
    }
}

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.rounded(13)).monospacedDigit().contentTransition(.numericText()).animation(.snappy, value: value)
        }
        .font(.system(size: 13))
    }
}

struct PanelNote: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}
