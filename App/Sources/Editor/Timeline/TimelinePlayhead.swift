//
//  TimelinePlayhead.swift
//  Slice
//
//  Created by rit3zh CX on 10/12/26.
//

import SliceCore
import SwiftUI

struct Playhead: View {
    static let width: CGFloat = 13
    var color: Color = .white
    var lineWidth: CGFloat = 2

    var body: some View {
        VStack(spacing: -1) {
            PinShape().fill(color).frame(width: Self.width, height: 16)
            Rectangle().fill(color).frame(width: lineWidth)
        }
        .frame(width: Self.width)
    }
}

/// The playhead: one layer moved to where the player is on every display refresh while playing. Only the layer moves,
/// not the timeline's views, so a frame costs next to nothing, and it always shows the player's real time, so it
/// can't run ahead or step back. Paused, it sits on the time being scrubbed to at once.
struct PlayheadTrack: View {
    let editor: EditorModel
    @ObservedObject var clock: PlaybackClock
    let pps: CGFloat
    let height: CGFloat

    var body: some View {
        PlayheadLayer(editor: editor, playing: clock.isPlaying, time: clock.time, pps: pps, height: height)
            .frame(height: height)
            .allowsHitTesting(false)
    }
}

private struct PlayheadLayer: NSViewRepresentable {
    let editor: EditorModel
    let playing: Bool
    let time: Double
    let pps: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> PlayheadLayerView { PlayheadLayerView(editor: editor) }

    func updateNSView(_ view: PlayheadLayerView, context: Context) {
        view.update(playing: playing, time: time, pps: pps, height: height)
    }
}

final class PlayheadLayerView: NSView {
    private weak var editor: EditorModel?
    private let head = CALayer()
    private let pin = CAShapeLayer()
    private let line = CALayer()
    private var shapedHeight: CGFloat?
    private var pps: CGFloat = 1
    private var playing = false
    private var link: CADisplayLink?

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    init(editor: EditorModel) {
        self.editor = editor
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        head.anchorPoint = CGPoint(x: 0.5, y: 0)
        head.shadowColor = NSColor.black.cgColor
        head.shadowOpacity = 0.5
        head.shadowRadius = 3
        head.shadowOffset = .zero
        pin.fillColor = NSColor.white.cgColor
        line.backgroundColor = NSColor.white.cgColor
        head.addSublayer(line)
        head.addSublayer(pin)
        layer?.addSublayer(head)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        [head, pin, line].forEach { $0.contentsScale = scale }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopLink() } else if playing { startLink() }
    }

    func update(playing: Bool, time: Double, pps: CGFloat, height: CGFloat) {
        if shapedHeight != height { shape(height: height) }
        self.pps = pps
        self.playing = playing
        if playing {
            startLink()
            tick()
        } else {
            stopLink()
            move(to: time)
        }
    }

    @objc private func tick() {
        guard let editor else { return }
        move(to: editor.liveTime)
    }

    private func move(to t: Double) {
        // On whole pixels, so the thin line stays crisp as it moves.
        let scale = window?.backingScaleFactor ?? 2
        let x = (CGFloat(t) * pps * scale).rounded() / scale
        guard head.position.x != x else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        head.position = CGPoint(x: x, y: 0)
        CATransaction.commit()
    }

    private func startLink() {
        guard link == nil, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    private func stopLink() {
        link?.invalidate()
        link = nil
    }

    private func shape(height: CGFloat) {
        shapedHeight = height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let w = Playhead.width
        head.bounds = CGRect(x: 0, y: 0, width: w, height: height)
        pin.frame = CGRect(x: 0, y: 0, width: w, height: 16)
        pin.path = PinShape().path(in: pin.bounds).cgPath
        line.frame = CGRect(x: (w - 2) / 2, y: 15, width: 2, height: max(height - 15, 0))
        let outline = CGMutablePath()
        outline.addPath(pin.path ?? CGMutablePath())
        outline.addRect(line.frame)
        head.shadowPath = outline
        CATransaction.commit()
    }
}

@Observable
final class Pointer {
    private(set) var x: CGFloat = 0
    private(set) var inside = false
    /// Hover regions on blocks briefly end the tracks' hover as the mouse crosses into them; ignore those blips.
    @ObservationIgnored private var leaving: DispatchWorkItem?

    func move(to x: CGFloat) {
        leaving?.cancel()
        leaving = nil
        self.x = x
        if !inside { inside = true }
    }

    func leave() {
        leaving?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.inside = false }
        leaving = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
}

struct GhostPlayhead: View {
    let pointer: Pointer
    @ObservedObject var clock: PlaybackClock
    let pps: CGFloat
    let height: CGFloat

    var body: some View {
        let x = pointer.x
        let shown = pointer.inside && abs(x - clock.time * pps) > 4
        Playhead(color: .white.opacity(0.28), lineWidth: 1)
            .frame(height: height)
            .offset(x: x - Playhead.width / 2)
            .transaction { $0.animation = nil }
            .animation(Theme.hover) { $0.opacity(shown ? 1 : 0) }
            .allowsHitTesting(false)
    }
}
