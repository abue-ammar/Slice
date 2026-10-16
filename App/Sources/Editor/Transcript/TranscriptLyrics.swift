//
//  TranscriptLyrics.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import AppKit
import SliceCore
import SwiftUI

struct TranscriptLyrics: View {
    let editor: EditorModel
    @ObservedObject private var clock: PlaybackClock
    let edit: (TranscriptWord) -> Void

    init(editor: EditorModel, edit: @escaping (TranscriptWord) -> Void) {
        self.editor = editor
        clock = editor.clock
        self.edit = edit
    }

    var body: some View {
        LyricsView(editor: editor, spoken: editor.lastSpokenWord(at: clock.time), playing: clock.isPlaying, edit: edit)
            .equatable()
    }
}

private struct LyricsView: View, Equatable {
    @ObservedObject var editor: EditorModel
    let spoken: Int?
    let playing: Bool
    let edit: (TranscriptWord) -> Void
    @State private var scroller = LyricsScroller()
    @State private var dragAnchor: Int?

    static func == (a: Self, b: Self) -> Bool {
        a.spoken == b.spoken && a.playing == b.playing && a.editor === b.editor
    }

    static let space = "lyrics"
    private static let anchor: CGFloat = 0.3

    private var focus: Int {
        (spoken ?? editor.spokenWords.first?.id).flatMap(editor.transcriptLine(containing:)) ?? 0
    }

    var body: some View {
        let focus = focus
        let focusing = playing && !scroller.browsing
        GeometryReader { geo in
            // Scrolled by the scroller rather than itself: the scroll view is here to keep lines out of sight from
            // taking clicks (on the timeline below, say), which clipping alone doesn't.
            ScrollView(.vertical) {
                SwiftUI.TimelineView(.animation(paused: scroller.kicks.isEmpty)) { timeline in
                    lines(focus: focus, focusing: focusing, now: timeline.date)
                        .padding(.horizontal, 22)
                        .padding(.top, 22)
                        .padding(.bottom, max(geo.size.height * 0.62, 90))
                        .frame(width: geo.size.width, alignment: .leading)
                        .coordinateSpace(.named(Self.space))
                        .gesture(dragToSelect)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scroller.contentHeight = $0 }
                        .offset(y: -scroller.y)
                }
            }
            .scrollDisabled(true)
            .scrollIndicators(.never)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { scroller.viewport = $0 }
        }
        .contentShape(Rectangle())
        .onHover { scroller.hovering = $0 }
        .mask(fade)
        .overlay(alignment: .bottom) { TranscriptBar(editor: editor, playing: playing).padding(10) }
        .onChange(of: focus) { _, line in follow(line, trail: true) }
        .onChange(of: playing) { _, now in if now { follow(focus, trail: true) } }
        .onChange(of: scroller.browsing) { _, browsing in if !browsing, playing { follow(focus, trail: true) } }
        .onAppear {
            scroller.startMonitoring()
            DispatchQueue.main.async { follow(focus, trail: false) }
        }
        .onDisappear { scroller.stopMonitoring() }
    }

    private func lines(focus: Int, focusing: Bool, now: Date) -> some View {
        let selection = editor.wordSelection
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(editor.transcriptLines) { line in
                let distance = abs(line.id - focus)
                LyricLine(words: editor.words[line.words], focused: line.id == focus,
                          said: min(max(spoken ?? -1, line.words.lowerBound - 1), line.words.upperBound - 1),
                          dim: playing ? 0.3 : 0.55, selection: selection.flatMap { overlap($0, line.words) }, actions: actions)
                    .equatable()
                    .blur(radius: focusing ? min(CGFloat(distance) * 1.2, 4) : 0)
                    .animation(.easeInOut(duration: 0.4).delay(line.id < focus ? 0 : min(Double(distance) * 0.05, 0.3)), value: focus)
                    .animation(.smooth(duration: 0.4), value: focusing)
                    .padding(.top, line.id == 0 ? 0 : line.startsParagraph ? 30 : 14)
                    .offset(y: scroller.offset(line: line.id, at: now))
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { scroller.lineFrames[line.id] = $0 }
            }
        }
    }

    private func overlap(_ selection: ClosedRange<Int>, _ line: Range<Int>) -> ClosedRange<Int>? {
        let lo = max(selection.lowerBound, line.lowerBound), hi = min(selection.upperBound, line.upperBound - 1)
        return lo <= hi ? lo ... hi : nil
    }

    private var actions: LineActions {
        LineActions(
            tap: { [editor] w in
                if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                    editor.selectSentence(containing: w.id)
                } else {
                    editor.selectWord(w.id, extend: NSEvent.modifierFlags.contains(.shift))
                }
            },
            jump: { [editor] w in
                editor.wordSelection = nil
                if let start = w.editedStart { editor.seek(to: start) }
            },
            edit: edit,
            selectSentence: { [editor] w in editor.selectSentence(containing: w.id) },
            cut: { [editor] w in
                if !(editor.wordSelection?.contains(w.id) ?? false) { editor.wordSelection = w.id ... w.id }
                editor.deleteSelectedWords()
            },
            restore: { [editor] w in
                if !(editor.wordSelection?.contains(w.id) ?? false) { editor.wordSelection = w.id ... w.id }
                editor.restoreSelectedWords()
            },
            frame: { [scroller] id, rect in scroller.wordFrames[id] = rect })
    }

    private func follow(_ line: Int, trail: Bool) {
        guard !scroller.browsing, let frame = scroller.lineFrames[line] else { return }
        if !playing, frame.minY >= scroller.y + 8, frame.maxY <= scroller.y + scroller.viewport - 80 { return }
        let target = frame.minY - scroller.viewport * Self.anchor
        scroller.scroll(to: target, trailFrom: trail ? (target > scroller.y ? max(line - 1, 0) : line + 1) : nil)
    }

    private var dragToSelect: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named(Self.space))
            .onChanged { v in
                if dragAnchor == nil { dragAnchor = scroller.word(at: v.startLocation) }
                guard let a = dragAnchor, let b = scroller.word(at: v.location) else { return }
                editor.wordSelection = min(a, b) ... max(a, b)
                editor.selection = nil
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private var fade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 26)
            Rectangle()
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 64)
            Color.clear.frame(height: 48)
        }
    }
}

private enum LyricStyle {
    static let font = Font.system(size: 20, weight: .bold)
    static let gap: CGFloat = 5
}

private struct LineActions {
    let tap: (TranscriptWord) -> Void
    let jump: (TranscriptWord) -> Void
    let edit: (TranscriptWord) -> Void
    let selectSentence: (TranscriptWord) -> Void
    let cut: (TranscriptWord) -> Void
    let restore: (TranscriptWord) -> Void
    let frame: (Int, CGRect) -> Void
}

private struct LyricLine: View, Equatable {
    let words: ArraySlice<TranscriptWord>
    let focused: Bool
    let said: Int
    let dim: Double
    let selection: ClosedRange<Int>?
    let actions: LineActions

    static func == (a: Self, b: Self) -> Bool {
        a.words == b.words && a.focused == b.focused && a.said == b.said && a.dim == b.dim && a.selection == b.selection
    }

    var body: some View {
        FlowLayout(spacing: 0, lineSpacing: 3) {
            ForEach(words) { w in
                let selected = selection?.contains(w.id) ?? false
                LyricWord(word: w, said: !w.isCut && w.id <= said, focused: focused, dim: dim, selected: selected,
                          joinsPrevious: selected && w.id > words.startIndex && selection?.contains(w.id - 1) == true,
                          joinsNext: selected && w.id + 1 < words.endIndex && selection?.contains(w.id + 1) == true,
                          actions: actions)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { if let first = words.first(where: { !$0.isCut }) { actions.jump(first) } }
    }
}

private struct LyricWord: View {
    let word: TranscriptWord
    let said: Bool
    let focused: Bool
    let dim: Double
    let selected: Bool
    let joinsPrevious: Bool
    let joinsNext: Bool
    let actions: LineActions
    @State private var hovering = false

    var body: some View {
        let r: CGFloat = 7
        let base = word.isCut ? 0.2 : selected ? 0.92 : dim
        Text(word.word.text)
            .font(LyricStyle.font)
            .strikethrough(word.isCut, color: .white.opacity(0.45))
            .modifier(WordFill(said: said ? 1 : 0, lit: focused ? 1 : base, dim: base))
            .animation(said ? .linear(duration: sayingTime) : .easeOut(duration: 0.25), value: said)
            .animation(.easeOut(duration: 0.4), value: focused)
            .animation(.smooth(duration: 0.35), value: dim)
            .animation(Theme.hover, value: selected)
            .padding(.horizontal, LyricStyle.gap / 2)
            .padding(.vertical, 2)
            .background(UnevenRoundedRectangle(topLeadingRadius: joinsPrevious ? 0 : r, bottomLeadingRadius: joinsPrevious ? 0 : r,
                                               bottomTrailingRadius: joinsNext ? 0 : r, topTrailingRadius: joinsNext ? 0 : r,
                                               style: .continuous)
                .fill(selected ? Theme.accent.opacity(0.32) : hovering ? Color.white.opacity(0.06) : .clear)
                .animation(Theme.hover, value: selected)
                .animation(Theme.hover, value: hovering))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture { actions.tap(word) }
            .contextMenu {
                Button("Edit Word…") { actions.edit(word) }
                Button("Select Sentence") { actions.selectSentence(word) }
                Divider()
                if word.isCut {
                    Button("Put Back") { actions.restore(word) }
                } else {
                    Button("Cut") { actions.cut(word) }
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(LyricsView.space)) } action: { actions.frame(word.id, $0) }
    }

    private var sayingTime: Double {
        guard let s = word.editedStart, let e = word.editedEnd else { return 0.3 }
        return min(max(e - s, 0.12), 0.6)
    }
}

private struct WordFill: ViewModifier, Animatable {
    var said: Double
    var lit: Double
    var dim: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(said, AnimatablePair(lit, dim)) }
        set { (said, lit, dim) = (newValue.first, newValue.second.first, newValue.second.second) }
    }

    func body(content: Content) -> some View {
        let edge = 0.45
        let head = said * (1 + edge)
        content.foregroundStyle(LinearGradient(stops: [
            .init(color: .white.opacity(lit), location: min(max(head - edge, 0), 1)),
            .init(color: .white.opacity(dim), location: min(max(head, 0), 1)),
        ], startPoint: .leading, endPoint: .trailing))
    }
}
