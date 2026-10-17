//
//  Music.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/1/26.
//

import Foundation

public enum MusicSource: Codable, Equatable, Hashable {
    case library(String)
    case file(String)
}

public struct MusicClip: Codable, Equatable, Identifiable {
    public var id: UUID
    public var source: MusicSource
    public var name: String
    public var start: Double
    public var end: Double
    public var toEnd: Bool
    public var offset: Double
    public var sourceDuration: Double
    public var loops: Bool
    public var volume: Double
    public var fadeIn: Double
    public var fadeOut: Double
    public var sourceLoudness: Double?

    public init(id: UUID = UUID(), source: MusicSource, name: String, start: Double, end: Double, toEnd: Bool = false,
                offset: Double = 0, sourceDuration: Double, loops: Bool = false, sourceLoudness: Double? = nil) {
        self.id = id
        self.source = source
        self.name = name
        self.start = start
        self.end = end
        self.toEnd = toEnd
        self.offset = offset
        self.sourceDuration = sourceDuration
        self.loops = loops
        self.sourceLoudness = sourceLoudness
        volume = 1
        fadeIn = 1
        fadeOut = 2
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        source = try c.decode(MusicSource.self, forKey: .source)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Music"
        start = try c.decodeIfPresent(Double.self, forKey: .start) ?? 0
        end = try c.decodeIfPresent(Double.self, forKey: .end) ?? 0
        toEnd = try c.decodeIfPresent(Bool.self, forKey: .toEnd) ?? false
        offset = try c.decodeIfPresent(Double.self, forKey: .offset) ?? 0
        sourceDuration = try c.decodeIfPresent(Double.self, forKey: .sourceDuration) ?? 0
        loops = try c.decodeIfPresent(Bool.self, forKey: .loops) ?? false
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1
        fadeIn = try c.decodeIfPresent(Double.self, forKey: .fadeIn) ?? 1
        fadeOut = try c.decodeIfPresent(Double.self, forKey: .fadeOut) ?? 2
        sourceLoudness = try c.decodeIfPresent(Double.self, forKey: .sourceLoudness)
    }

    public static let minLength = 0.3
    public static let minFade = 0.02
    static let loopCrossfade = 1.2
    static let targetLoudness = -18.0

    public static func normalizationGain(loudness: Double) -> Double {
        min(max(pow(10, (targetLoudness - loudness) / 20), 0.25), 2)
    }

    public func timelineRange(duration: Double) -> ClosedRange<Double>? {
        let s = max(start, 0)
        var e = toEnd ? duration : min(end, duration)
        if !loops { e = min(e, s + max(sourceDuration - offset, 0)) }
        return e - s > 0.01 ? s ... e : nil
    }

    public func nominalEnd(duration: Double) -> Double {
        var e = toEnd ? max(duration, start) : end
        if !loops { e = min(e, start + max(sourceDuration - offset, 0)) }
        return e
    }

    public func pieces(duration: Double) -> [MusicPiece] {
        let d = sourceDuration
        guard let r = timelineRange(duration: duration), d > 0.05 else { return [] }
        var from = loops ? offset.truncatingRemainder(dividingBy: d) : min(max(offset, 0), d)
        if from < 0 { from += d }
        var out = [MusicPiece(lane: 0, at: r.lowerBound, from: from, length: min(d - from, r.upperBound - r.lowerBound))]
        guard loops else { return out }
        while let last = out.last, last.end < r.upperBound - 1e-6 {
            let overlap = min(Self.loopCrossfade, last.length / 2, d / 4)
            let at = last.end - overlap
            out.append(MusicPiece(lane: out.count % 2, at: at, from: 0, length: min(d, r.upperBound - at)))
        }
        return out
    }

    public func sourceTime(at t: Double, duration: Double) -> Double? {
        pieces(duration: duration).last { $0.at <= t && t <= $0.end }.map { $0.from + (t - $0.at) }
    }

    func fadeEnvelope(_ r: ClosedRange<Double>) -> GainEnvelope {
        let len = r.upperBound - r.lowerBound
        var fi = max(fadeIn, Self.minFade), fo = max(fadeOut, Self.minFade)
        if fi + fo > len {
            let k = len / (fi + fo)
            fi *= k
            fo *= k
        }
        return GainEnvelope(GainEnvelope.ramp(from: r.lowerBound, 0, to: r.lowerBound + fi, 1, curve: Self.fadeCurve)
            + GainEnvelope.ramp(from: r.upperBound - fo, 1, to: r.upperBound, 0, curve: Self.fadeCurve))
    }

    static func fadeCurve(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}

public struct MusicPiece: Equatable {
    public var lane: Int
    public var at: Double
    public var from: Double
    public var length: Double
    public var end: Double { at + length }
}

public struct AudioSettings: Codable, Equatable {
    public var musicVolume = 0.35
    public var musicMuted = false
    public var normalizeMusic = true
    public var ducking = true
    public var duckAmount = 0.65
    public var duckAttack = 0.3
    public var duckRelease = 0.8

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AudioSettings()
        musicVolume = try c.decodeIfPresent(Double.self, forKey: .musicVolume) ?? d.musicVolume
        musicMuted = try c.decodeIfPresent(Bool.self, forKey: .musicMuted) ?? d.musicMuted
        normalizeMusic = try c.decodeIfPresent(Bool.self, forKey: .normalizeMusic) ?? d.normalizeMusic
        ducking = try c.decodeIfPresent(Bool.self, forKey: .ducking) ?? d.ducking
        duckAmount = try c.decodeIfPresent(Double.self, forKey: .duckAmount) ?? d.duckAmount
        duckAttack = try c.decodeIfPresent(Double.self, forKey: .duckAttack) ?? d.duckAttack
        duckRelease = try c.decodeIfPresent(Double.self, forKey: .duckRelease) ?? d.duckRelease
    }
}

// MARK: - Project

public struct MusicPlacement: Equatable {
    public var id: UUID
    public var source: MusicSource
    public var pieces: [MusicPiece]
}

public struct MusicLane {
    public var clipID: UUID
    public var lane: Int
    public var pieces: [MusicPiece]
    public var envelope: GainEnvelope
}

extension Project {
    public var musicPlacements: [MusicPlacement] {
        let d = duration
        return music.map { MusicPlacement(id: $0.id, source: $0.source, pieces: $0.pieces(duration: d)) }
    }

    func speechAudible(_ clip: Clip) -> Bool {
        if clip.micFile != nil { return micVolume > 0 }
        return clip.screenAudioFile != nil && screenAudioVolume > 0
    }

    public var speechSpans: [TimeSpan] {
        var out: [TimeSpan] = []
        for seg in segments {
            let clip = clips[seg.clipIndex]
            guard let spans = clip.speech, speechAudible(clip), !seg.isSpedUp else { continue }
            for s in spans where s.end > seg.sourceStart && s.start < seg.sourceEnd {
                out.append(TimeSpan(start: seg.edited(local: max(s.start, seg.sourceStart)),
                                    end: seg.edited(local: min(s.end, seg.sourceEnd))))
            }
        }
        return out.sorted { $0.start < $1.start }
    }

    public var duckingEnvelope: GainEnvelope {
        guard audio.ducking, audio.duckAmount > 0.001 else { return .constant(1) }
        return .ducking(spans: speechSpans, level: 1 - min(audio.duckAmount, 1), attack: audio.duckAttack,
                        release: audio.duckRelease)
    }

    public func musicGain(for clip: MusicClip) -> Double {
        guard !audio.musicMuted else { return 0 }
        var g = audio.musicVolume * clip.volume
        if audio.normalizeMusic, let l = clip.sourceLoudness { g *= MusicClip.normalizationGain(loudness: l) }
        return max(g, 0)
    }

    public func musicShape(for clip: MusicClip, ducking: GainEnvelope? = nil) -> GainEnvelope {
        guard let r = clip.timelineRange(duration: duration) else { return .constant(0) }
        return clip.fadeEnvelope(r) * (ducking ?? duckingEnvelope)
    }

    public func musicLanes() -> [MusicLane] {
        let duck = duckingEnvelope
        var out: [MusicLane] = []
        for clip in music {
            let pieces = clip.pieces(duration: duration)
            guard !pieces.isEmpty, let r = clip.timelineRange(duration: duration) else { continue }
            let shape = (clip.fadeEnvelope(r) * duck).scaled(musicGain(for: clip))
            for lane in Set(pieces.map(\.lane)).sorted() {
                let mine = pieces.filter { $0.lane == lane }
                let env = (shape * GainEnvelope.crossfade(pieces: pieces, lane: lane)).clamped(to: 0 ... 4)
                out.append(MusicLane(clipID: clip.id, lane: lane, pieces: mine, envelope: env))
            }
        }
        return out
    }

    // MARK: Editing music

    public func musicGap(around t: Double, excluding: UUID? = nil) -> ClosedRange<Double> {
        let d = duration
        let others = music.filter { $0.id != excluding }.compactMap { $0.timelineRange(duration: d) }
        let lo = others.filter { $0.upperBound <= t + 1e-9 }.map(\.upperBound).max() ?? 0
        let hi = others.filter { $0.lowerBound >= t - 1e-9 }.map(\.lowerBound).min() ?? d
        return lo ... max(lo, hi)
    }

    public mutating func moveMusic(_ id: UUID, to start: Double) {
        guard let i = music.firstIndex(where: { $0.id == id }) else { return }
        let c = music[i], d = duration
        let len = c.nominalEnd(duration: d) - c.start
        let space = musicGap(around: c.start + len / 2, excluding: id)
        let s = max(min(start, space.upperBound - len), space.lowerBound)
        music[i].start = s
        music[i].end = min(s + len, space.upperBound)
        music[i].toEnd = c.toEnd && music[i].end >= d - 0.01
    }

    public mutating func trimMusic(_ id: UUID, start newStart: Double? = nil, end newEnd: Double? = nil) {
        guard let i = music.firstIndex(where: { $0.id == id }) else { return }
        var c = music[i]
        let d = duration
        let space = musicGap(around: c.start + 0.001, excluding: id)
        if let newStart {
            let end = c.nominalEnd(duration: d)
            var s = min(max(newStart, space.lowerBound), end - MusicClip.minLength)
            if !c.loops { s = max(s, c.start - c.offset) }
            c.offset += s - c.start
            if c.loops, c.sourceDuration > 0 {
                c.offset = c.offset.truncatingRemainder(dividingBy: c.sourceDuration)
                if c.offset < 0 { c.offset += c.sourceDuration }
            }
            if !c.toEnd { c.end = end }
            c.start = s
        }
        if let newEnd {
            var e = max(min(newEnd, space.upperBound), c.start + MusicClip.minLength)
            if !c.loops { e = min(e, c.start + max(c.sourceDuration - c.offset, MusicClip.minLength)) }
            c.end = e
            c.toEnd = e >= d - 0.01
        }
        music[i] = c
    }
}
