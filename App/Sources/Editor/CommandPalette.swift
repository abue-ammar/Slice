//
//  CommandPalette.swift
//  Slice
//
//  Created by rit3zh CX on 10/2/26.
//

import AppKit
import SwiftUI

struct CommandPalette: View {
    let commands: [EditorCommand]
    let close: () -> Void
    let run: (EditorCommand) -> Void

    @State private var query = ""
    @State private var group: PaletteGroup?
    @State private var selectedID: String?
    @State private var firingID: String?
    @State private var shakeID: String?
    @State private var shakes = 0
    @State private var lastPointer: CGPoint?
    @State private var pointerMoved = false
    @State private var keyEvent: PaletteKey?
    @State private var pressed: Set<UInt16> = []
    @State private var monitor: Any?
    @FocusState private var searchFocused: Bool
    @Namespace private var namespace

    init(commands: [EditorCommand], close: @escaping () -> Void, run: @escaping (EditorCommand) -> Void) {
        self.commands = commands
        self.close = close
        self.run = run
        _selectedID = State(initialValue: commands.first(where: \.enabled)?.id)
    }

    private var results: [EditorCommand] {
        let scored = commands.enumerated()
            .filter { group == nil || $0.element.group == group }
            .map { (i: $0.offset, c: $0.element, s: $0.element.score(query)) }
            .filter { $0.s > 0 }
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        return scored.sorted { searching && $0.s != $1.s ? $0.s > $1.s : $0.i < $1.i }.map(\.c)
    }

    private func sections(_ r: [EditorCommand]) -> [(title: String, items: [EditorCommand])] {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty { return r.isEmpty ? [] : [("Best matches", r)] }
        return PaletteGroup.allCases.compactMap { g in
            let items = r.filter { $0.group == g }
            return items.isEmpty ? nil : (g.title, items)
        }
    }

    var body: some View {
        let results = self.results
        let ids = results.map(\.id)
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        VStack(spacing: 0) {
            searchBar
            chips
            Rectangle().fill(Theme.stroke).frame(height: 1)
            list(sections(results), ids: ids)
            footer(count: results.count)
        }
        .frame(width: 580)
        .clipShape(shape)
        // The shadow is cast by the plain backing shape, not the whole palette, so it's drawn once instead of being
        // worked out again from every row and glyph on each frame of the animation.
        .background(shape.fill(Color(white: 0.095)).shadow(color: .black.opacity(0.45), radius: 28, y: 14))
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.16), .white.opacity(0.05)],
                                                   startPoint: .top, endPoint: .bottom)))
        .onAppear {
            // The field has to be in the window before it can take focus.
            DispatchQueue.main.async { searchFocused = true }
            installMonitor()
        }
        .onDisappear { if let monitor { NSEvent.removeMonitor(monitor) } }
        .onChange(of: ids) { _, ids in
            if selectedID.map({ !ids.contains($0) }) ?? true {
                withAnimation(.smooth(duration: 0.2)) { selectedID = results.first(where: \.enabled)?.id ?? ids.first }
            }
        }
    }

    // MARK: Parts

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: query.isEmpty ? "magnifyingglass" : "xmark.circle.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 18)
                .onTapGesture { query = "" }
            TextField("Search commands", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .focused($searchFocused)
            KeyCap(key: "esc", pressed: pressed.contains(53))
                .onTapGesture(perform: close)
        }
        .padding(.horizontal, 18)
        .frame(height: 54)
    }

    private var chips: some View {
        HStack(spacing: 2) {
            chip(nil, "All")
            ForEach(PaletteGroup.allCases) { chip($0, $0.title) }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func chip(_ g: PaletteGroup?, _ title: String) -> some View {
        let on = group == g
        return Button { withAnimation(Theme.slide) { group = g } } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(on ? Color.primary : Color.secondary)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background {
                    if on {
                        Capsule().fill(Theme.thumb).matchedGeometryEffect(id: "chip", in: namespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func list(_ sections: [(title: String, items: [EditorCommand])], ids: [String]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if sections.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "text.magnifyingglass").font(.system(size: 20)).foregroundStyle(.tertiary)
                        Text("Nothing matches “\(query)”").font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 90)
                    .transition(.opacity)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(sections, id: \.title) { section in
                            Text(section.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 12)
                                .padding(.top, 12)
                                .padding(.bottom, 4)
                            ForEach(section.items) { cmd in
                                row(cmd)
                                    .id(cmd.id)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
            .scrollIndicators(.never)
            .frame(height: 360)
            .animation(.smooth(duration: 0.22), value: ids)
            .onContinuousHover(coordinateSpace: .global) { phase in
                if case let .active(p) = phase, p != lastPointer {
                    if lastPointer != nil { pointerMoved = true }
                    lastPointer = p
                }
            }
            .onChange(of: keyEvent) { _, event in
                guard let event else { return }
                handle(event)
                if event.code == 125 || event.code == 126, let id = selectedID {
                    withAnimation(.smooth(duration: 0.2)) { proxy.scrollTo(id) }
                }
            }
        }
    }

    private func row(_ cmd: EditorCommand) -> some View {
        let selected = cmd.id == selectedID
        return HStack(spacing: 12) {
            Image(systemName: cmd.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected && cmd.enabled ? Color.white : Color.secondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected && cmd.enabled ? Theme.accent : Theme.control))
            HStack(spacing: 8) {
                highlighted(cmd.title)
                    .font(.system(size: 13, weight: .medium))
                if let detail = cmd.detail {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            if !cmd.keys.isEmpty { KeyCombo(keys: cmd.keys) }
        }
        .padding(.horizontal, 10)
        .frame(height: 42)
        .opacity(cmd.enabled ? 1 : 0.4)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(firingID == cmd.id ? Theme.accent.opacity(0.25) : Theme.thumb)
                    .matchedGeometryEffect(id: "selection", in: namespace)
            }
        }
        .modifier(Shake(animatableData: shakeID == cmd.id ? CGFloat(shakes) : 0))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside, pointerMoved, selectedID != cmd.id {
                withAnimation(.smooth(duration: 0.18)) { selectedID = cmd.id }
            }
        }
        .onTapGesture { fire(cmd) }
        .animation(.smooth(duration: 0.2), value: selected)
    }

    private func highlighted(_ title: String) -> Text {
        let q = query.trimmingCharacters(in: .whitespaces)
        var s = AttributedString(title)
        s.foregroundColor = q.isEmpty ? .primary : .primary.opacity(0.75)
        if !q.isEmpty, let r = s.range(of: q, options: .caseInsensitive) {
            s[r].foregroundColor = Theme.accent
        }
        return Text(s)
    }

    private func footer(count: Int) -> some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                KeyCap(key: "↑", pressed: pressed.contains(126))
                KeyCap(key: "↓", pressed: pressed.contains(125))
                Text("Move")
            }
            HStack(spacing: 6) {
                KeyCap(key: "↩", pressed: pressed.contains(36) || pressed.contains(76))
                Text("Run")
            }
            HStack(spacing: 6) {
                KeyCap(key: "⇥", pressed: pressed.contains(48))
                Text("Category")
            }
            Spacer()
            Text("\(count) commands")
                .font(.rounded(11).monospacedDigit())
                .contentTransition(.numericText())
                .animation(.smooth(duration: 0.2), value: count)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .frame(height: 38)
        .background(Color.white.opacity(0.025))
        .overlay(alignment: .top) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    // MARK: Keys

    private func installMonitor() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let code = event.keyCode
            let handled: Set<UInt16> = [125, 126, 36, 76, 53, 48]
            let commandK = event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "k"
            guard handled.contains(code) || commandK else { return event }
            if event.type == .keyUp {
                pressed.remove(code)
                return nil
            }
            pressed.insert(code)
            // A key held while ⌘ is down may never send its key up.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { pressed.remove(code) }
            keyEvent = PaletteKey(code: commandK ? 53 : code, shift: event.modifierFlags.contains(.shift))
            return nil
        }
    }

    private func handle(_ e: PaletteKey) {
        let ids = sections(results).flatMap(\.items).map(\.id)
        switch e.code {
        case 125, 126:
            guard !ids.isEmpty else { return }
            pointerMoved = false
            let i = selectedID.flatMap { ids.firstIndex(of: $0) } ?? -1
            let next = e.code == 125 ? (i + 1) % ids.count : (i - 1 + ids.count) % ids.count
            withAnimation(.smooth(duration: 0.18)) { selectedID = ids[next] }
        case 36, 76:
            if let cmd = results.first(where: { $0.id == selectedID }) { fire(cmd) }
        case 48:
            let all: [PaletteGroup?] = [nil] + PaletteGroup.allCases
            let i = all.firstIndex(of: group) ?? 0
            withAnimation(Theme.slide) { group = all[(i + (e.shift ? all.count - 1 : 1)) % all.count] }
        case 53:
            close()
        default: break
        }
    }

    private func fire(_ cmd: EditorCommand) {
        selectedID = cmd.id
        guard cmd.enabled else {
            shakeID = cmd.id
            withAnimation(.linear(duration: 0.32)) { shakes += 1 }
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            return
        }
        firingID = cmd.id
        run(cmd)
    }
}

private struct PaletteKey: Equatable {
    let code: UInt16
    let shift: Bool
    let id = UUID()
}

private struct Shake: GeometryEffect {
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 5 * sin(animatableData * .pi * 4), y: 0))
    }
}
