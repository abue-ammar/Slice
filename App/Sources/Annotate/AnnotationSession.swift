//
//  AnnotationSession.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import AppKit
import AVFoundation
import SliceCore

/// What's drawn over the screen during one recording. Points are global AppKit points (origin bottom-left of the
/// primary display) and host-clock seconds, the clock the takes and the pointer log run on.
@MainActor
final class AnnotationSession: ObservableObject {
    static let colors: [RGBA] = [
        RGBA(1, 0.27, 0.27), RGBA(1, 0.8, 0.18), RGBA(0.24, 0.82, 0.42),
        RGBA(0.16, 0.47, 1), RGBA(1, 1, 1), RGBA(0.08, 0.08, 0.09),
    ]
    static let widths: [Double] = [3, 5, 9]

    @Published var isActive = false
    /// A label is being typed, so keys belong to it.
    @Published var isTyping = false
    @Published var tool: Annotation.Tool {
        didSet { UserDefaults.standard.set(tool.rawValue, forKey: "annotate.tool") }
    }
    @Published var colorIndex: Int {
        didSet { UserDefaults.standard.set(colorIndex, forKey: "annotate.color") }
    }
    @Published var widthIndex: Int {
        didSet { UserDefaults.standard.set(widthIndex, forKey: "annotate.width") }
    }
    /// On screen now, oldest first.
    @Published private(set) var shown: [Annotation] = []
    private(set) var drawing: Annotation?
    /// Undone or cleared, kept with when they went so the video takes them away at the same moment.
    private var gone: [Annotation] = []
    /// Called with the area (global points) that needs drawing again, or nil for everything.
    var onChange: ((CGRect?) -> Void)?

    init() {
        let d = UserDefaults.standard
        tool = d.string(forKey: "annotate.tool").flatMap(Annotation.Tool.init) ?? .pen
        colorIndex = min(max(d.integer(forKey: "annotate.color"), 0), Self.colors.count - 1)
        widthIndex = d.object(forKey: "annotate.width") == nil ? 1 : min(max(d.integer(forKey: "annotate.width"), 0), Self.widths.count - 1)
    }

    var color: RGBA { Self.colors[colorIndex] }
    var width: Double { Self.widths[widthIndex] }
    var canUndo: Bool { !shown.isEmpty }

    nonisolated static var now: Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    nonisolated static func time(of event: NSEvent) -> Double {
        event.timestamp + now - ProcessInfo.processInfo.systemUptime
    }

    // MARK: - Drawing

    func begin(at p: CGPoint, time t: Double) {
        finish()
        drawing = Annotation(tool: tool, color: color, width: width, points: [.init(t: t, x: p.x, y: p.y)])
        changed(drawing)
    }

    func extend(to p: CGPoint, time t: Double, constrained: Bool) {
        guard var a = drawing, let anchor = a.points.first else { return }
        let before = bounds(a)
        var q = p
        if constrained { q = Self.constrain(p, from: anchor.location, tool: a.tool) }
        if a.tool == .pen || a.tool == .highlighter {
            guard let last = a.points.last, hypot(q.x - last.x, q.y - last.y) >= 0.75 else { return }
        }
        a.points.append(.init(t: t, x: q.x, y: q.y))
        drawing = a
        onChange?(before.union(bounds(a)))
    }

    func finish() {
        guard let a = drawing else { return }
        drawing = nil
        if a.points.count > 1 || a.tool == .pen || a.tool == .highlighter { shown.append(a) }
        onChange?(bounds(a))
    }

    func addLabel(_ text: String, at p: CGPoint, time t: Double) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let a = Annotation(tool: .text, color: color, width: width, points: [.init(t: t, x: p.x, y: p.y)], text: text)
        shown.append(a)
        changed(a)
    }

    func undo() {
        finish()
        guard var last = shown.popLast() else { return }
        last.end = Self.now
        gone.append(last)
        changed(last)
    }

    func clear() {
        finish()
        let t = Self.now
        gone += shown.map { var a = $0; a.end = t; return a }
        shown = []
        onChange?(nil)
    }

    /// Forgets everything drawn, once a recording has kept it or nothing was recorded.
    func reset() {
        drawing = nil
        gone = []
        shown = []
        onChange?(nil)
    }

    var isEmpty: Bool { shown.isEmpty && drawing == nil }

    /// Everything drawn, as a take over `captureRect` (global top-left points) logs it: points as fractions of it.
    func recorded(in captureRect: CGRect) -> [Annotation] {
        let map = CursorLogger.mapping(captureRect)
        return (gone + shown + [drawing].compactMap { $0 }).map { $0.mapped { map(NSPoint(x: $0.x, y: $0.y)) } }
    }

    private func changed(_ a: Annotation?) {
        onChange?(a.map(bounds))
    }

    private func bounds(_ a: Annotation) -> CGRect {
        AnnotationPainter.bounds(of: a, count: a.points.count, scale: 1) { $0 }
    }

    /// Lines and arrows held to 45° steps, boxes and ovals kept square, as with Shift in most drawing apps.
    static func constrain(_ p: CGPoint, from a: CGPoint, tool: Annotation.Tool) -> CGPoint {
        let dx = p.x - a.x, dy = p.y - a.y
        switch tool {
        case .line, .arrow:
            let length = hypot(dx, dy)
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            return CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
        case .rectangle, .ellipse:
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: a.x + (dx < 0 ? -side : side), y: a.y + (dy < 0 ? -side : side))
        default:
            return p
        }
    }
}
