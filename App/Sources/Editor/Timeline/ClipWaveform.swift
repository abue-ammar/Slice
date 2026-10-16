//
//  ClipWaveform.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import Accelerate
import SliceCore
import SwiftUI

/// What a take plays: its voice (enhanced when that's on) and its screen or imported audio, at the project's volumes.
struct ClipAudio: Hashable {
    var mic: URL?
    var screen: URL?
    var micGain: Float
    var screenGain: Float

    var urls: [URL] { [mic, screen].compactMap { $0 } }
    var isEmpty: Bool { mic == nil && screen == nil }
}

/// A take's mixed loudness over source time, scaled to its own loudest moment at full volume.
struct Waveform: Equatable {
    let levels: [Float]
    let bucketsPerSecond: Double

    init(mic: AudioSummary?, screen: AudioSummary?, micGain: Float, screenGain: Float) {
        let m = mic?.levels ?? [], s = screen?.levels ?? []
        var out = [Float](repeating: 0, count: max(m.count, s.count))
        var peak: Float = 0
        for i in out.indices {
            let a = i < m.count ? m[i] : 0, b = i < s.count ? s[i] : 0
            peak = max(peak, a * a + b * b)
            out[i] = (a * a * micGain * micGain + b * b * screenGain * screenGain).squareRoot()
        }
        let scale = peak > 0 ? 1 / peak.squareRoot() : 0
        levels = out.map { min($0 * scale, 1) }
        bucketsPerSecond = mic?.bucketsPerSecond ?? screen?.bucketsPerSecond ?? 40
    }

    /// The loudest level between two source times; narrower than a bucket, it eases between neighbouring buckets.
    func level(from a: Double, to b: Double) -> Float {
        guard !levels.isEmpty else { return 0 }
        let fa = a * bucketsPerSecond - 0.5, fb = b * bucketsPerSecond - 0.5
        let lo = max(Int(fa.rounded(.up)), 0), hi = min(Int(fb.rounded(.down)), levels.count - 1)
        if hi > lo {
            var peak: Float = 0
            levels.withUnsafeBufferPointer { vDSP_maxv($0.baseAddress! + lo, 1, &peak, vDSP_Length(hi - lo + 1)) }
            return peak
        }
        let c = (fa + fb) / 2
        guard c > -1, c < Double(levels.count) else { return 0 }
        let i = Int(c.rounded(.down)), f = Float(c - Double(i))
        func at(_ k: Int) -> Float { k < 0 ? levels[0] : k < levels.count ? levels[k] : 0 }
        return at(i) + (at(i + 1) - at(i)) * f
    }
}

@MainActor
private enum WaveformCache {
    private static var entries: [ClipAudio: Waveform] = [:]

    static func waveform(for audio: ClipAudio, in summaries: [URL: AudioSummary]) -> Waveform? {
        if let w = entries[audio] { return w }
        let mic = audio.mic.flatMap { summaries[$0] }, screen = audio.screen.flatMap { summaries[$0] }
        guard mic != nil || screen != nil else { return nil }
        let w = Waveform(mic: mic, screen: screen, micGain: audio.micGain, screenGain: audio.screenGain)
        // Only keep it once every source has loaded, so a late one isn't left out.
        if (audio.mic == nil) == (mic == nil), (audio.screen == nil) == (screen == nil) {
            if entries.count > 64 { entries.removeAll() }
            entries[audio] = w
        }
        return w
    }
}

/// The take's audio drawn across a section chip; `sourceStart` is the source time at the chip's leading edge.
struct ClipWaveformView: View {
    let audio: ClipAudio
    let sourceStart: Double
    let pps: CGFloat
    let strength: Double

    @ObservedObject private var summaries = AudioSummaries.shared
    private static let tint = Color(red: 0.76, green: 0.86, blue: 1)

    var body: some View {
        let waveform = WaveformCache.waveform(for: audio, in: summaries.summaries)
        Canvas { ctx, size in
            guard let waveform else { return }
            let base = size.height - 3, reach = size.height * 0.6
            let step: CGFloat = 2
            var points: [CGPoint] = []
            points.reserveCapacity(Int(size.width / step) + 2)
            var x: CGFloat = 0
            while true {
                // The chip sits 1pt right of its start time.
                let t = sourceStart + Double(x + 1) / Double(pps), half = Double(step / 2) / Double(pps)
                let level = pow(Double(waveform.level(from: t - half, to: t + half)), 0.6)
                points.append(CGPoint(x: x, y: base - CGFloat(level) * reach))
                if x >= size.width { break }
                x = min(x + step, size.width)
            }
            var line = Path()
            line.move(to: points[0])
            for i in points.indices.dropFirst() {
                let p = points[i - 1], q = points[i]
                line.addQuadCurve(to: CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2), control: p)
            }
            line.addLine(to: points[points.count - 1])
            var fill = line
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            ctx.fill(fill, with: .linearGradient(Gradient(colors: [Self.tint.opacity(0.26), Self.tint.opacity(0.1)]),
                                                 startPoint: CGPoint(x: 0, y: base - reach), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(line, with: .color(Self.tint.opacity(0.7)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        }
        .opacity(waveform == nil ? 0 : strength)
        .animation(Theme.hover, value: waveform == nil)
        .allowsHitTesting(false)
        .task(id: audio.urls) {
            await withTaskGroup(of: Void.self) { group in
                for url in audio.urls { group.addTask { _ = await AudioSummaries.shared.load(url) } }
            }
        }
    }
}
