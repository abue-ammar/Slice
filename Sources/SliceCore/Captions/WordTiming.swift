//
//  WordTiming.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/16/26.
//

import Foundation

/// Turns what a recogniser reports into `Word`s timed well enough to cut on, highlight and caption.
///
/// Parakeet reports sub-word tokens, each with its own time, so words are simply their tokens joined. Apple's
/// recognisers report runs of text with one time range each, and a run sometimes holds several words. Spreading a
/// run's time over its words by letter count is only a guess, so each guessed boundary is moved to the quietest
/// moment of the recording near it (the gap between two words), and every word is trimmed to the speech inside its
/// range. Times only ever move inside the range the recogniser gave; nothing is invented outside it.
public enum WordTiming {
    public struct Piece: Equatable, Sendable {
        public var text: String
        public var start: Double
        public var end: Double
        public var confidence: Double?

        public init(text: String, start: Double, end: Double, confidence: Double? = nil) {
            self.text = text
            self.start = start
            self.end = end
            self.confidence = confidence
        }
    }

    /// Words from sub-word tokens, where a token beginning with a space starts a new word.
    public static func words(fromTokens tokens: [Piece]) -> [Word] {
        var out: [Word] = []
        var confidences: [Double] = []
        func finish() {
            guard !out.isEmpty, !confidences.isEmpty else { return }
            out[out.count - 1].confidence = confidences.reduce(0, +) / Double(confidences.count)
            confidences = []
        }
        for token in tokens {
            let startsWord = token.text.first?.isWhitespace ?? false
            let text = token.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            if startsWord || out.isEmpty {
                finish()
                out.append(Word(text: text, start: token.start, end: token.end))
            } else {
                out[out.count - 1].text += text
                out[out.count - 1].end = max(out[out.count - 1].end, token.end)
            }
            if let c = token.confidence { confidences.append(c) }
        }
        finish()
        return tidy(out)
    }

    /// Words from runs that each carry one time range, split and trimmed against the recording's levels when known.
    public static func words(fromSegments segments: [Piece], levels: SpeechLevels?) -> [Word] {
        var out: [Word] = []
        for seg in segments where seg.end > seg.start {
            let pieces = seg.text.split(whereSeparator: \.isWhitespace).map(String.init)
            guard !pieces.isEmpty else { continue }
            let (start, end) = pieces.count > 1 ? levels?.trimmed(seg.start, seg.end) ?? (seg.start, seg.end) : (seg.start, seg.end)
            let bounds = boundaries(for: pieces, from: start, to: end, levels: levels)
            for (i, text) in pieces.enumerated() {
                var w = Word(text: text, start: bounds[i], end: bounds[i + 1], confidence: seg.confidence)
                if let levels { (w.start, w.end) = levels.trimmed(w.start, w.end) }
                // The first word of a result can stay stretched over the silence before it (a noisy room hides the
                // gap); cap it at a generous spoken length ending where it really ends.
                let plausible = 0.3 + 0.1 * Double(text.count)
                if w.end - w.start > plausible { w.start = w.end - plausible }
                out.append(w)
            }
        }
        return tidy(out)
    }

    static func boundaries(for pieces: [String], from start: Double, to end: Double, levels: SpeechLevels?) -> [Double] {
        let n = pieces.count
        guard n > 1 else { return [start, end] }
        let total = Double(pieces.reduce(0) { $0 + $1.count })
        var cumulative = 0.0
        var out = [start]
        let span = end - start, minimum = min(0.05, span / Double(n) / 2)
        let reach = min(0.25, 0.4 * span / Double(n))
        for k in 1 ..< n {
            cumulative += Double(pieces[k - 1].count)
            let guess = start + span * (total > 0 ? cumulative / total : Double(k) / Double(n))
            let lo = max(out[k - 1] + minimum, guess - reach)
            let hi = min(end - minimum * Double(n - k), guess + reach)
            var b = min(max(guess, lo), hi)
            if let levels, lo < hi, let quiet = levels.quietest(from: lo, to: hi, near: guess), levels.level(at: quiet) < levels.level(at: b) - 3 {
                b = quiet
            }
            out.append(b)
        }
        out.append(end)
        return out
    }

    /// Sorted, with punctuation joined to the word before it and no word running into the next.
    public static func tidy(_ words: [Word]) -> [Word] {
        var merged: [Word] = []
        for w in words.sorted(by: { $0.start < $1.start }) {
            if let last = merged.last, w.text.allSatisfy({ $0.isPunctuation }) {
                merged[merged.count - 1].text = last.text + w.text
                merged[merged.count - 1].end = max(last.end, w.end)
            } else {
                merged.append(w)
            }
        }
        for i in merged.indices.dropLast() where merged[i].end > merged[i + 1].start {
            merged[i].end = max(merged[i + 1].start, merged[i].start + 0.01)
        }
        return merged
    }
}

/// A recording's loudness over time, used to place word boundaries in the gaps between words.
public struct SpeechLevels: Sendable {
    public let frame: Double
    public let levels: [Double]
    public let threshold: Double

    public init?(levels: [Double], frame: Double) {
        guard let threshold = AudioAnalysis.speechThreshold(levels: levels) else { return nil }
        self.init(levels: levels, frame: frame, threshold: threshold)
    }

    init(levels: [Double], frame: Double, threshold: Double) {
        self.frame = frame
        self.levels = levels
        self.threshold = threshold
    }

    public init?(url: URL, frame: Double = 0.01) {
        guard let levels = AudioAnalysis.levels(in: url, frame: frame) else { return nil }
        self.init(levels: levels, frame: frame)
    }

    func index(_ t: Double) -> Int { min(max(Int(t / frame), 0), max(levels.count - 1, 0)) }

    func level(at t: Double) -> Double { levels.isEmpty ? -100 : levels[index(t)] }

    /// The middle of the quietest stretch between the two times, the one nearest `near` if there are several.
    func quietest(from a: Double, to b: Double, near: Double? = nil) -> Double? {
        guard !levels.isEmpty, b > a else { return nil }
        let lo = index(a), hi = index(b)
        guard let low = levels[lo ... hi].min() else { return nil }
        var runs: [ClosedRange<Int>] = []
        for i in lo ... hi where levels[i] <= low + 1 {
            if let last = runs.last, last.upperBound == i - 1 { runs[runs.count - 1] = last.lowerBound ... i } else { runs.append(i ... i) }
        }
        let centers = runs.map { (Double($0.lowerBound + $0.upperBound) / 2 + 0.5) * frame }
        let target = near ?? (a + b) / 2
        return centers.min { abs($0 - target) < abs($1 - target) }
    }

    /// The range shrunk to the speech inside it, with a little room either side; unchanged if it holds no speech.
    func trimmed(_ start: Double, _ end: Double) -> (Double, Double) {
        guard !levels.isEmpty, end > start else { return (start, end) }
        let lo = index(start), hi = index(end)
        guard let first = (lo ... hi).first(where: { levels[$0] > threshold }),
              let last = (lo ... hi).last(where: { levels[$0] > threshold }) else { return (start, end) }
        let s = max(start, Double(first) * frame - 0.03), e = min(end, Double(last + 1) * frame + 0.05)
        return e - s >= 0.08 ? (s, e) : (start, end)
    }
}
