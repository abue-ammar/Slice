//
//  PanelContainers.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import SliceCore
import SwiftUI

struct MoreOptions<Content: View>: View {
    let title: String
    let pinned: Bool
    /// Open or folded. Kept here rather than in `@AppStorage`, whose updates land outside the animation (so the
    /// options popped rather than unfolding); saved to the defaults alongside.
    @State private var expanded: Bool
    private let key: String
    @ViewBuilder var content: Content
    @State private var hovering = false
    @State private var height: CGFloat = 0

    init(_ title: String = "More options", id: String, pinned: Bool = false, @ViewBuilder content: () -> Content) {
        self.title = title
        self.pinned = pinned
        key = "moreOptions.\(id)"
        _expanded = State(initialValue: UserDefaults.standard.bool(forKey: "moreOptions.\(id)"))
        self.content = content()
    }

    private var open: Bool { expanded || pinned }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                let next = !open
                withAnimation(Self.unfold) { expanded = next }
                UserDefaults.standard.set(next, forKey: key)
            } label: {
                HStack(spacing: 5) {
                    Text(title).font(.system(size: 12, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(open ? 90 : 0))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(hovering ? Color.primary : Color.secondary)
                .frame(minHeight: 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(pinned)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = $0 }
                .opacity(open ? 1 : 0)
                .offset(y: open ? 0 : -6)
                .frame(height: open ? (height > 0 ? height : nil) : 0, alignment: .top)
                .clipped()
                .allowsHitTesting(open)
                .accessibilityHidden(!open)
        }
        .animation(Self.unfold, value: pinned)
    }

    private static var unfold: Animation { .smooth(duration: 0.34) }
}

struct ChoiceChips<Value: Hashable>: View {
    let options: [Value]
    let selected: Value?
    let title: (Value) -> String
    var rounded = false
    let pick: (Value) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                let on = option == selected
                Button { withAnimation(.snappy) { pick(option) } } label: {
                    Text(title(option))
                        .font(rounded ? .rounded(12).monospacedDigit() : .system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(on ? Theme.accent : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? Theme.accent.opacity(0.15) : Theme.control))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .animation(Theme.hover, value: on)
            }
        }
    }
}

struct Tile<Content: View>: View {
    let selected: Bool
    let action: () -> Void
    @ViewBuilder var content: Content
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay { content }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.22 : 0.08)))
                .padding(2.5)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(selected ? 1 : 0), lineWidth: 2))
                .brightness(hovering && !selected ? 0.06 : 0)
                .contentShape(Rectangle())
        }
        .buttonStyle(TilePress())
        .onHover { hovering = $0 }
        .animation(Theme.hover, value: hovering)
        .animation(Theme.hover, value: selected)
    }
}

private struct TilePress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

struct PagedGrid<Item: Hashable, Cell: View>: View {
    let items: [Item]
    var columns = 6
    var rows = 2
    @ViewBuilder var cell: (Item) -> Cell
    @State private var page = 0
    @State private var forward = true

    private var perPage: Int { columns * rows }
    private var pageCount: Int { max(Int((Double(items.count) / Double(perPage)).rounded(.up)), 1) }

    var body: some View {
        let current = min(page, pageCount - 1)
        let slice = Array(items.dropFirst(current * perPage).prefix(perPage))
        VStack(spacing: 10) {
            ZStack {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
                    ForEach(slice, id: \.self) { cell($0) }
                    ForEach(slice.count ..< perPage, id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                }
                .id(current)
                .transition(.push(from: forward ? .trailing : .leading))
            }
            .clipped()

            if pageCount > 1 {
                HStack(spacing: 14) {
                    Button { go(current - 1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(IconButtonStyle(size: 22, iconSize: 11))
                        .disabled(current == 0)
                    HStack(spacing: 5) {
                        ForEach(0 ..< pageCount, id: \.self) { i in
                            Capsule()
                                .fill(i == current ? Theme.accent : Color.white.opacity(0.2))
                                .frame(width: i == current ? 14 : 5, height: 5)
                                .contentShape(Rectangle().inset(by: -4))
                                .onTapGesture { go(i) }
                        }
                    }
                    Button { go(current + 1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(IconButtonStyle(size: 22, iconSize: 11))
                        .disabled(current == pageCount - 1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: items.count) { _, _ in page = min(page, pageCount - 1) }
    }

    private func go(_ p: Int) {
        let p = min(max(p, 0), pageCount - 1)
        forward = p > page
        withAnimation(Theme.slide) { page = p }
    }
}

struct EmptyState<Action: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var action: Action

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.control))
            VStack(spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            action.padding(.top, 4)
        }
        .frame(maxWidth: 260)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }
}

extension EmptyState where Action == EmptyView {
    init(symbol: String, title: String, message: String) {
        self.init(symbol: symbol, title: title, message: message) { EmptyView() }
    }
}
