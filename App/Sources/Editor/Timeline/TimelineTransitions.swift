//
//  TimelineTransitions.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import SliceCore
import SwiftUI

struct AddTransitionButton: View {
    static let size: CGFloat = 16
    let visible: Bool
    let add: (ClipTransition.Kind) -> Void
    @State private var hovering = false
    @State private var picking = false

    var body: some View {
        let shown = visible || picking
        Button { picking = true } label: {
            Image(systemName: "plus")
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(.white.opacity(hovering || picking ? 1 : 0.8))
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(Theme.window))
                .overlay(Circle().strokeBorder(Color.white.opacity(hovering || picking ? 0.5 : 0.2), lineWidth: 1))
                .contentShape(Circle().inset(by: -4))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(shown ? 1 : 0)
        .allowsHitTesting(shown)
        .animation(Theme.hover, value: shown)
        .animation(Theme.hover, value: hovering)
        .help("Add a transition")
        .popover(isPresented: $picking, arrowEdge: .bottom) {
            TransitionPicker(selected: nil) { kind in
                picking = false
                add(kind)
            }
            .padding(5)
        }
    }
}

struct TransitionPicker: View {
    let selected: ClipTransition.Kind?
    let pick: (ClipTransition.Kind) -> Void
    var width: CGFloat? = 180

    var body: some View {
        VStack(spacing: 1) {
            ForEach(ClipTransition.Kind.allCases, id: \.self) { kind in
                TransitionPickerRow(kind: kind, selected: kind == selected) { pick(kind) }
            }
        }
        .frame(width: width)
    }
}

struct TransitionPickerRow: View {
    let kind: ClipTransition.Kind
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(kind.name).font(.system(size: 12.5)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)) }
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(hovering ? 0.09 : selected ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
    }
}

struct TransitionBlock: View {
    static let height: CGFloat = 20
    let placed: PlacedTransition
    let pps: CGFloat
    let selected: Bool
    let select: () -> Void
    let setDuration: (Double) -> Void
    let remove: () -> Void
    @State private var hovering = false
    @State private var dragStart: Double?

    static func width(_ p: PlacedTransition, pps: CGFloat) -> CGFloat { max(p.duration * pps, 24) }

    var body: some View {
        let lit = hovering || selected || dragStart != nil
        let shape = Capsule(style: .continuous)
        Image(systemName: placed.transition.kind.symbol)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.white.opacity(lit ? 1 : 0.85))
            .frame(width: Self.width(placed, pps: pps), height: Self.height)
            .background(shape.fill(Theme.window.opacity(0.85)))
            .overlay(shape.strokeBorder(Color.white.opacity(selected || dragStart != nil ? 0.9 : hovering ? 0.45 : 0.22),
                                        lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .leading) { edge(leading: true) }
            .overlay(alignment: .trailing) { edge(leading: false) }
            .contentShape(shape)
            .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: lit)
            .onTapGesture(perform: select)
            .contextMenu {
                Button("Remove Transition", role: .destructive, action: remove)
            }
            .help("\(placed.transition.kind.name), \(String(format: "%.1fs", placed.duration))")
    }

    private func edge(leading: Bool) -> some View {
        Color.clear
            .frame(width: 7, height: Self.height)
            .contentShape(Rectangle())
            .pointerStyle(.columnResize)
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { v in
                    if dragStart == nil {
                        dragStart = placed.duration
                        select()
                    }
                    let dx = (leading ? -v.translation.width : v.translation.width) * 2 / pps
                    setDuration((dragStart ?? placed.duration) + dx)
                }
                .onEnded { _ in dragStart = nil })
            .opacity(Self.width(placed, pps: pps) >= 30 ? 1 : 0)
            .allowsHitTesting(Self.width(placed, pps: pps) >= 30)
    }
}
