//
//  Subtitles.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/4/26.
//

import Foundation

public struct Word: Codable, Equatable, Sendable {
    public var text: String
    public var start: Double
    public var end: Double
    public var hidden: Bool?
    /// How sure the recogniser was, 0–1, when it says.
    public var confidence: Double?

    public init(text: String, start: Double, end: Double, confidence: Double? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct Transcript: Codable, Equatable, Sendable {
    public var locale: String
    public var words: [Word]
    /// Which recogniser made it (a `TranscriptionBackend` raw value); older transcripts don't say.
    public var engine: String?

    public init(locale: String, words: [Word], engine: String? = nil) {
        self.locale = locale
        self.words = words
        self.engine = engine
    }
}

public struct SubtitleSettings: Codable, Equatable {
    public enum Position: String, Codable, CaseIterable { case bottom, top }

    public var burnIn = false
    public var position: Position = .bottom
    public var size = 0.045
    public var highlightWord = true
    public var maxCharacters = 48

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SubtitleSettings()
        burnIn = try c.decodeIfPresent(Bool.self, forKey: .burnIn) ?? d.burnIn
        position = try c.decodeIfPresent(Position.self, forKey: .position) ?? d.position
        size = try c.decodeIfPresent(Double.self, forKey: .size) ?? d.size
        highlightWord = try c.decodeIfPresent(Bool.self, forKey: .highlightWord) ?? d.highlightWord
        maxCharacters = try c.decodeIfPresent(Int.self, forKey: .maxCharacters) ?? d.maxCharacters
    }
}

public struct Caption: Equatable {
    public struct TimedWord: Equatable {
        public var text: String
        public var start: Double
        public var end: Double
        public var clipIndex: Int = 0
        public var wordIndex: Int = 0
    }

    public var start: Double
    public var end: Double
    public var words: [TimedWord]
    public var text: String { words.map(\.text).joined(separator: " ") }
}

public enum CaptionBuilder {
    public static func captions(project: Project, transcripts: [UUID: Transcript], maxCharacters: Int) -> [Caption] {
        var timed: [Caption.TimedWord] = []
        for (i, clip) in project.clips.enumerated() {
            guard let t = transcripts[clip.id] else { continue }
            for (wi, w) in t.words.enumerated() where w.hidden != true {
                // Sped-up stretches play silent, so their words aren't captioned.
                guard let seg = project.segment(clipIndex: i, local: (w.start + w.end) / 2), !seg.isSpedUp else { continue }
                let s = seg.edited(local: (w.start + w.end) / 2)
                let half = (w.end - w.start) / 2
                timed.append(.init(text: w.text, start: max(s - half, 0), end: s + half, clipIndex: i, wordIndex: wi))
            }
        }
        timed.sort { $0.start < $1.start }

        var out: [Caption] = []
        var current: [Caption.TimedWord] = []
        func flush() {
            guard let first = current.first, let last = current.last else { return }
            out.append(Caption(start: first.start, end: last.end, words: current))
            current = []
        }
        for w in timed {
            if let last = current.last {
                let chars = current.reduce(0) { $0 + $1.text.count + 1 } + w.text.count
                let endsSentence = last.text.last.map { ".?!".contains($0) } ?? false
                if chars > maxCharacters || w.start - last.end > 0.7 || (endsSentence && current.count >= 3) {
                    flush()
                }
            }
            current.append(w)
        }
        flush()

        var merged: [Caption] = []
        for c in out {
            let lastEndsSentence = merged.last?.words.last?.text.last.map { ".?!".contains($0) } ?? true
            if let last = merged.last, !lastEndsSentence, c.words.count <= 2, c.start - last.end < 0.4,
               last.text.count + 1 + c.text.count <= maxCharacters + 16 {
                merged[merged.count - 1].words += c.words
                merged[merged.count - 1].end = c.end
            } else {
                merged.append(c)
            }
        }
        out = merged

        for i in out.indices {
            let next = i + 1 < out.count ? out[i + 1].start : .infinity
            out[i].end = min(max(out[i].end + 0.3, out[i].start + 0.8), next)
        }
        return out
    }

    public static func caption(at t: Double, in captions: [Caption]) -> Caption? {
        captions.last { $0.start <= t && t < $0.end }
    }
}

public enum CaptionMotion {
    public static let inDuration = 0.4
    public static let outDuration = 0.26
    public static let swapDuration = 0.5
    static let wordSwapDuration = 0.34
    public static let bridge = 0.6
    public static let wordDuration = 0.28

    public struct State: Equatable {
        public var index: Int
        public var previous: Int?
        public var shape: Double = 1
        public var outgoing: Double = 1
        public var incoming: Double = 1
        public var opacity: Double = 1
        public var blur: Double = 0
        public var scale: Double = 1
        public var drop: Double = 0
    }

    public static func handsOver(_ i: Int, in captions: [Caption]) -> Bool {
        i + 1 < captions.count && captions[i + 1].start - captions[i].end < bridge
    }

    public static func lastStarted(at t: Double, in captions: [Caption]) -> Int? {
        var lo = 0, hi = captions.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if captions[mid].start <= t { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? lo - 1 : nil
    }

    public static func spring(_ t: Double, response: Double = 0.36, damping: Double = 0.76) -> Double {
        guard t > 0 else { return 0 }
        let w = 2 * Double.pi / response, wd = w * (1 - damping * damping).squareRoot()
        return 1 - exp(-damping * w * t) * (cos(wd * t) + damping * w / wd * sin(wd * t))
    }

    public static func shapeEase(_ t: Double) -> Double {
        t >= swapDuration ? 1 : spring(t)
    }

    public static func state(at t: Double, in captions: [Caption]) -> State? {
        guard let i = lastStarted(at: t, in: captions) else { return nil }
        let c = captions[i]
        var s = State(index: i)
        if !handsOver(i, in: captions), t >= c.end {
            let o = (t - c.end) / outDuration
            guard o < 1 else { return nil }
            s.blur = 1 - pow(1 - o, 2)
            s.opacity = 1 - o * o * (3 - 2 * o)
            s.scale = 1 - 0.04 * o * o
        }
        let since = t - c.start
        if i > 0, handsOver(i - 1, in: captions) {
            if since < swapDuration {
                let p = since / wordSwapDuration
                s.previous = i - 1
                s.shape = shapeEase(since)
                s.outgoing = min(p / 0.5, 1)
                s.incoming = min(max((p - 0.2) / 0.8, 0), 1)
            }
        } else if since < inDuration {
            let a = min(since / 0.3, 1)
            let settle = 1 - pow(1 - a, 3)
            s.opacity *= 1 - pow(1 - min(a / 0.6, 1), 2)
            s.blur = max(s.blur, 1 - settle)
            let k = spring(since, response: 0.34)
            s.scale *= 0.92 + 0.08 * k
            s.drop = 0.35 * (1 - k)
        }
        return s
    }

    public static func focus(of word: Caption.TimedWord, at t: Double) -> Double {
        let p = min(max((t - word.start + 0.06) / wordDuration, 0), 1)
        return p * p * p * (p * (p * 6 - 15) + 10)
    }
}

public enum SRT {
    public static func make(_ captions: [Caption]) -> String {
        captions.enumerated().map { i, c in
            "\(i + 1)\n\(stamp(c.start)) --> \(stamp(c.end))\n\(c.text)\n"
        }.joined(separator: "\n")
    }

    static func stamp(_ t: Double) -> String {
        let ms = Int((max(t, 0) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60000 % 60, ms / 1000 % 60, ms % 1000)
    }
}

public enum SubtitleEdit {
    public static func apply(_ newText: String, to words: [Word]) -> [Word] {
        let old = words.map(\.text)
        let new = newText.split(whereSeparator: \.isWhitespace).map(String.init)
        let diff = new.difference(from: old)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case let .remove(offset, _, _): removed.insert(offset)
            case let .insert(offset, _, _): inserted.insert(offset)
            }
        }
        var out = words
        var i = 0, j = 0
        var pending: [String] = []
        var lastVisible: Int?
        func attach(_ extra: [String], before index: Int?) {
            guard !extra.isEmpty else { return }
            if let v = lastVisible {
                out[v].text += " " + extra.joined(separator: " ")
            } else if let n = index {
                out[n].text = extra.joined(separator: " ") + " " + out[n].text
            }
        }
        while i < old.count || j < new.count {
            if j < new.count, inserted.contains(j) {
                pending.append(new[j])
                j += 1
            } else if i < old.count, removed.contains(i) {
                if pending.isEmpty {
                    out[i].hidden = true
                } else {
                    out[i].text = pending.joined(separator: " ")
                    out[i].hidden = nil
                    pending = []
                    lastVisible = i
                }
                i += 1
            } else if i < old.count {
                attach(pending, before: i)
                pending = []
                out[i].hidden = nil
                lastVisible = i
                i += 1
                j += 1
            } else {
                break
            }
        }
        if !pending.isEmpty {
            if let v = lastVisible {
                attach(pending, before: nil)
            } else if let first = out.indices.first {
                out[first].text = pending.joined(separator: " ")
                out[first].hidden = nil
            }
        }
        return out
    }
}
