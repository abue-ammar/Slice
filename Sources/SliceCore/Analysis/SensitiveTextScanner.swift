//
//  SensitiveTextScanner.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import AVFoundation
import Vision

/// Reads the edit's screen every half second and covers each email, card number or key it finds with a blur for as
/// long as it's on screen. Frames that look the same as the last one read reuse what was found there.
///
/// Text being typed only matches once it's whole (`jane@exam` isn't an address yet), so each new find looks back
/// through the frames before it: while the same spot shows the start of it, the blur starts there too, and covers
/// the text as it's typed.
public enum SensitiveTextScanner {
    static let interval = 0.5
    static let unchanged = 2
    /// How far back typing is followed: longer than anyone takes to type an address or paste a key.
    static let lookBack = 30.0
    /// Fewer typed characters than this say nothing yet.
    static let typedMinimum = 3

    struct Found {
        var kind: SensitiveText.Kind
        var text: String
        var rect: CGRect
    }

    /// A line of text read on screen; `box` places a part of it, in the same space as `Found.rect`.
    struct Line {
        var text: String
        var box: (Range<String.Index>) -> CGRect?
    }

    struct Track {
        var found: Found
        var first: Double
        var last: Double
    }

    public static func scan(project: Project, bundle: ProjectBundle,
                            progress: @escaping @Sendable (Double) -> Void) async throws -> [RedactBlock] {
        let duration = project.duration
        guard duration > 0 else { return [] }
        let times = Array(stride(from: 0, to: duration, by: interval))
        var runs: [(clip: Int, samples: [(edited: Double, local: Double)])] = []
        for t in times {
            guard let (ci, local) = project.sourceTime(edited: t) else { continue }
            if runs.last?.clip == ci { runs[runs.count - 1].samples.append((t, local)) } else { runs.append((ci, [(t, local)])) }
        }

        var open: [Track] = [], closed: [Track] = []
        var previous: (clip: Int, grid: [UInt8], found: [Found], lines: [Line])?
        var history: [(t: Double, lines: [Line])] = []
        var done = 0
        for run in runs {
            let clip = project.clips[run.clip]
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: bundle.file(clip.screenFile)))
            generator.maximumSize = CGSize(width: 2560, height: 2560)
            generator.appliesPreferredTrackTransform = true
            let tolerance = CMTime(value: 1, timescale: 20)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
            let edited = Dictionary(run.samples.map { (Int(($0.local * 1000).rounded()), $0.edited) }) { a, _ in a }
            history = []
            for await result in generator.images(for: run.samples.map { CMTime(seconds: $0.local, preferredTimescale: 600) }) {
                try Task.checkCancellation()
                done += 1
                progress(Double(done) / Double(times.count))
                guard let image = try? result.image,
                      let t = edited[Int((result.requestedTime.seconds * 1000).rounded())] else { continue }
                let grid = ScreenChange.luma(image) ?? []
                let found: [Found], lines: [Line]
                if let p = previous, p.clip == run.clip, same(p.grid, grid) {
                    (found, lines) = (p.found, p.lines)
                } else {
                    (found, lines) = read(image)
                }
                previous = (run.clip, grid, found, lines)
                follow(found, at: t, open: &open, closed: &closed)
                for i in open.indices where open[i].first == t { typedBack(&open[i], history: history) }
                history.append((t, lines))
                history.removeAll { $0.t < t - lookBack }
            }
        }
        closed += open
        return closed.map { track in
            RedactBlock(start: max(track.first - interval, 0), end: min(track.last + interval, duration),
                        rect: RedactBlock.clamped(track.found.rect), style: .blur, strength: 0.6, isAuto: true,
                        label: track.found.kind.label)
        }.sorted { $0.start < $1.start }
    }

    static func same(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        return zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= unchanged }
    }

    static func recognise(_ image: CGImage) -> [Found] { read(image).found }

    static func read(_ image: CGImage) -> (found: [Found], lines: [Line]) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: image).perform([request])
        var found: [Found] = [], lines: [Line] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = Line(text: candidate.string) { range in
                guard let box = (try? candidate.boundingBox(for: range))?.boundingBox else { return nil }
                return CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
            }
            lines.append(line)
            for match in SensitiveText.matches(in: candidate.string) {
                guard let rect = line.box(match.range) else { continue }
                found.append(Found(kind: match.kind, text: String(candidate.string[match.range]), rect: padded(rect)))
            }
        }
        return (found, lines)
    }

    static func padded(_ rect: CGRect) -> CGRect {
        let pad = rect.height * 0.35
        return rect.insetBy(dx: -pad, dy: -pad)
    }

    /// Starts a new find back as far as the frames before it show it being typed in the same place.
    static func typedBack(_ track: inout Track, history: [(t: Double, lines: [Line])]) {
        let target = track.found
        for (t, lines) in history.reversed() {
            let typed = lines.lazy.compactMap { line -> CGRect? in
                guard let range = typedPrefix(of: target.text, in: line.text), let box = line.box(range) else { return nil }
                return inPlace(box, of: target.rect) ? box : nil
            }.first
            guard let typed else { return }
            track.first = t
            track.found.rect = track.found.rect.union(padded(typed))
        }
    }

    /// Where `line` shows the start of `text`: the longest run from a word's start that `text` begins with, at least
    /// `typedMinimum` characters. It needn't reach the end of the line, as the caret over a letter can misread it.
    static func typedPrefix(of text: String, in line: String) -> Range<String.Index>? {
        let target = Array(text.lowercased())
        let chars = Array(line.lowercased())
        guard chars.count == line.count, target.count >= typedMinimum else { return nil }
        var best: (start: Int, length: Int)?
        for start in chars.indices where start == 0 || chars[start - 1].isWhitespace {
            var k = 0
            while k < target.count, start + k < chars.count, chars[start + k] == target[k] { k += 1 }
            if k >= typedMinimum, k > best?.length ?? 0 { best = (start, k) }
        }
        guard let best else { return nil }
        let from = line.index(line.startIndex, offsetBy: best.start)
        return from ..< line.index(from, offsetBy: best.length)
    }

    /// Typed text starts where the finished text does, on the same line.
    static func inPlace(_ typed: CGRect, of found: CGRect) -> Bool {
        let h = typed.height
        return h > 0 && (found.minY ... found.maxY).contains(typed.midY) && abs(typed.minX - found.minX) < h * 1.5
    }

    /// Extends the tracks still on screen with what was found at `t`, and closes the ones that weren't seen again.
    static func follow(_ found: [Found], at t: Double, open: inout [Track], closed: inout [Track]) {
        var next: [Track] = []
        for f in found {
            if let i = open.firstIndex(where: { $0.found.kind == f.kind && overlap($0.found.rect, f.rect) > 0.5 }) {
                var track = open.remove(at: i)
                track.found.rect = track.found.rect.union(f.rect)
                track.last = t
                next.append(track)
            } else {
                next.append(Track(found: f, first: t, last: t))
            }
        }
        closed += open
        open = next
    }

    static func overlap(_ a: CGRect, _ b: CGRect) -> Double {
        let i = a.intersection(b)
        guard !i.isNull, i.width > 0, i.height > 0 else { return 0 }
        let smaller = min(a.width * a.height, b.width * b.height)
        return Double(i.width * i.height / max(smaller, 1e-9))
    }
}
