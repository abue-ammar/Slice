//
//  LiveTakeAnalyzer.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/15/26.
//

import CoreGraphics
import CoreVideo
import Foundation

/// Analyses a take while it records, so stopping doesn't start a pass over the finished files: how the screen
/// changes around each click (for smart zoom, saved beside the take as it goes), where the pointer hovers something
/// that reacts, and which camera frames glitch.
///
/// Only the few pixels each check needs are kept (a 96×60 overview at most 15 times a second, the patch under the
/// pointer, a 32×18 sample), read on a utility queue that holds at most two frames: if it falls behind, a
/// frame is skipped rather than holding more of the recorder's buffers.
public final class LiveTakeAnalyzer: @unchecked Sendable {
    public struct Results: Sendable {
        public var screenChanges: [ScreenChange.Entry]
        public var hoverMoments: [Double]
        public var cameraGlitches: [TimeSpan]
    }

    public static let cacheName = "screen-changes.json"
    static let gridInterval = 1.0 / 15
    static let pendingLimit = 120

    private let cacheURL: URL
    private let pointSize: CGSize
    private let inFlightLimit: Int
    private let work = DispatchQueue(label: "take.analysis", qos: .utility)

    // Capture side, under `lock`.
    private let lock = NSLock()
    private var pointer: CGPoint?
    private var lastGrid = -Double.infinity
    private var inFlight = 0
    private var skipped = false

    // Everything below lives on `work`. Times are host-clock seconds until they're saved.
    private var origin: Double?
    private var samples: [CursorLog.Sample] = []
    private var grids: [(t: Double, grid: [UInt8])] = []
    private var clicks: [(t: Double, point: CGPoint)] = []
    private var measured: [(t: Double, point: CGPoint, result: ScreenChange.Result)] = []
    private var frames: [Frame] = []
    private var hovers: [Double] = []
    private var camera: [(t: Double, thumb: [Float])] = []
    private var glitches: [TimeSpan] = []
    private var saveScheduled = false

    public convenience init(folder: URL, pointSize: CGSize) {
        self.init(folder: folder, pointSize: pointSize, inFlightLimit: 2)
    }

    init(folder: URL, pointSize: CGSize, inFlightLimit: Int) {
        cacheURL = folder.appendingPathComponent(Self.cacheName)
        self.pointSize = pointSize
        self.inFlightLimit = inFlightLimit
    }

    // MARK: - Input

    /// The host time the take's files start at; saved times are measured from it.
    public func start(at t: Double) {
        work.async { self.origin = t }
    }

    /// A screen frame as it's written to the take, BGRA.
    public func screenFrame(_ buffer: CVPixelBuffer, at t: Double) {
        let accepted = lock.withLock { () -> (point: CGPoint?, grid: Bool, afterGap: Bool)? in
            guard inFlight < inFlightLimit else {
                skipped = true
                return nil
            }
            inFlight += 1
            let grid = t - lastGrid >= Self.gridInterval
            if grid { lastGrid = t }
            defer { skipped = false }
            return (pointer, grid, skipped)
        }
        guard let accepted else { return }
        let pointSize = pointSize
        work.async {
            let frame = Frame(buffer, t: t, pointer: accepted.point, pointSize: pointSize, grid: accepted.grid,
                              afterGap: accepted.afterGap)
            self.lock.withLock { self.inFlight -= 1 }
            if let frame { self.add(frame) }
        }
    }

    /// A pointer position from the cursor log, mapped the same way.
    public func pointer(at t: Double, _ point: CGPoint) {
        lock.withLock { pointer = point }
        work.async {
            let sample = CursorLog.Sample(t: t, x: point.x, y: point.y)
            guard t.isFinite, point.x.isFinite, point.y.isFinite else { return }
            let i = self.samples.lastIndex { $0.t <= t }.map { $0 + 1 } ?? 0
            self.samples.insert(sample, at: i)
            self.evaluateHovers(force: false)
        }
    }

    public func click(at t: Double, _ point: CGPoint) {
        work.async {
            self.clicks.append((t, point))
            self.resolveClicks(final: nil)
        }
    }

    /// A camera frame's thumbnail, for frames that went into the file.
    public func cameraFrame(_ thumb: [Float], at t: Double) {
        work.async {
            self.camera.append((t, thumb))
            if self.camera.count == 3 {
                if CameraGlitchDetector.isGlitch(previous: self.camera[0].thumb, frame: self.camera[1].thumb, next: self.camera[2].thumb) {
                    self.glitches.append(TimeSpan(start: self.camera[1].t, end: self.camera[2].t))
                }
                self.camera.removeFirst()
            }
        }
    }

    /// Settles what's still waiting (the last clicks, the last frames), saves, and hands back times within the take.
    public func finish(duration: Double) async -> Results {
        await withCheckedContinuation { continuation in
            work.async {
                let origin = self.origin ?? 0
                self.evaluateHovers(force: true)
                self.resolveClicks(final: origin + max(duration - 0.02, 0))
                self.save()
                continuation.resume(returning: Results(
                    screenChanges: self.entries(),
                    hoverMoments: self.hovers.map { $0 - origin },
                    cameraGlitches: self.glitches.map { TimeSpan(start: $0.start - origin, end: $0.end - origin) }))
            }
        }
    }

    // MARK: - Screen changes

    private func add(_ frame: Frame) {
        if let grid = frame.grid {
            grids.append((frame.t, grid))
            // A few seconds is plenty: a click is settled 0.7 s after it. The newest frame from before that stays, as
            // the screen still showed it.
            if let keep = grids.lastIndex(where: { $0.t < frame.t - 4 }), keep > 0 { grids.removeFirst(keep) }
            resolveClicks(final: nil)
        }
        frames.append(frame)
        evaluateHovers(force: false)
    }

    private func grid(atOrBefore t: Double) -> [UInt8]? {
        grids.last { $0.t <= t }?.grid ?? grids.first?.grid
    }

    /// Measures every click whose "after" moment has been seen; with `final` (the take's last moment), all of them.
    private func resolveClicks(final last: Double?) {
        guard !clicks.isEmpty, let newest = grids.last?.t else { return }
        var waiting: [(t: Double, point: CGPoint)] = []
        for c in clicks {
            let target = c.t + ScreenChange.after
            guard last != nil || newest >= target,
                  let before = grid(atOrBefore: max(c.t - ScreenChange.before, origin ?? -.infinity)),
                  let after = grid(atOrBefore: last.map { min(target, $0) } ?? target) else {
                if last == nil { waiting.append(c) }
                continue
            }
            measured.append((c.t, c.point, ScreenChange.compare(before, after, at: c.point)))
        }
        let resolvedAny = waiting.count < clicks.count
        clicks = waiting
        if resolvedAny, last == nil { scheduleSave() }
    }

    private func entries() -> [ScreenChange.Entry] {
        guard let origin else { return [] }
        return measured.map { ScreenChange.Entry(t: $0.t - origin, x: $0.point.x, y: $0.point.y, result: $0.result) }
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        work.asyncAfter(deadline: .now() + 1) {
            self.saveScheduled = false
            self.save()
        }
    }

    private func save() {
        guard origin != nil, let data = try? JSONEncoder().encode(entries()) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }

    // MARK: - Hover

    /// Compares each frame with the one before once the pointer log has caught up with it, as `HoverDetector.scan`
    /// does over the file. Frames wait at most `pendingLimit` deep (the log pauses while the pointer is over Slice).
    private func evaluateHovers(force: Bool) {
        while frames.count >= 2 {
            let previous = frames[0], current = frames[1]
            guard force || frames.count > Self.pendingLimit || (samples.last?.t ?? -.infinity) >= current.t else { return }
            if isHover(from: previous, to: current), current.t - (hovers.last ?? -.infinity) > 1.0 / 30 {
                hovers.append(current.t)
            }
            frames.removeFirst()
        }
    }

    private func isHover(from a: Frame, to b: Frame) -> Bool {
        guard !b.afterGap, samples.count > 1, pointSize.width > 0, pointSize.height > 0,
              a.width == b.width, a.height == b.height, a.width > 0, a.height > 0 else { return false }
        let limit = HoverDetector.threshold << 8
        let pointer = (HoverDetector.position(in: samples, at: a.t), HoverDetector.position(in: samples, at: b.t))
        return HoverDetector.isHover(width: b.width, height: b.height, pointer: pointer, pointSize: pointSize,
                                     changed: { x, y in
                                         guard let la = a.patch?.luma(x, y), let lb = b.patch?.luma(x, y) else { return nil }
                                         return abs(Int(la) - Int(lb)) > limit
                                     },
                                     global: { gx, gy in
                                         let i = gy * 32 + gx
                                         return abs(Int(a.overview[i]) - Int(b.overview[i])) > limit
                                     })
    }
}

// MARK: - Frames

extension LiveTakeAnalyzer {
    /// What's kept of one frame: luma as `HoverDetector` weighs it (29 B + 150 G + 77 R).
    struct Frame {
        struct Patch {
            let x0: Int, y0: Int, width: Int, height: Int
            let values: [UInt16]

            func luma(_ x: Int, _ y: Int) -> UInt16? {
                let dx = x - x0, dy = y - y0
                guard dx >= 0, dy >= 0, dx < width, dy < height else { return nil }
                return values[dy * width + dx]
            }
        }

        let t: Double
        let width: Int
        let height: Int
        let overview: [UInt16]
        let patch: Patch?
        let grid: [UInt8]?
        /// Frames before this one were skipped, so it isn't compared with the one kept before it.
        let afterGap: Bool

        init?(_ buffer: CVPixelBuffer, t: Double, pointer: CGPoint?, pointSize: CGSize, grid wantGrid: Bool, afterGap: Bool = false) {
            guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer), row = CVPixelBufferGetBytesPerRow(buffer)
            guard w > 0, h > 0, let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
            let p = UnsafePointer(base.assumingMemoryBound(to: UInt8.self))
            self.t = t
            width = w
            height = h
            self.afterGap = afterGap
            var overview = [UInt16](repeating: 0, count: 32 * 18)
            for gy in 0 ..< 18 {
                let line = p + ((2 * gy + 1) * h / 36) * row
                for gx in 0 ..< 32 {
                    let px = line + ((2 * gx + 1) * w / 64) * 4
                    overview[gy * 32 + gx] = UInt16(29 * Int(px[0]) + 150 * Int(px[1]) + 77 * Int(px[2]))
                }
            }
            self.overview = overview
            patch = Self.patch(p, width: w, height: h, row: row, pointer: pointer, pointSize: pointSize)
            grid = wantGrid ? ScreenChange.luma(buffer) : nil
        }

        /// Wide enough for the hover circle wherever the pointer gets to before the log catches up with this frame.
        private static func patch(_ p: UnsafePointer<UInt8>, width w: Int, height h: Int, row: Int, pointer: CGPoint?,
                                  pointSize: CGSize) -> Patch? {
            guard let pointer, pointSize.width > 0, pointer.x.isFinite, pointer.y.isFinite else { return nil }
            let ppp = Double(w) / pointSize.width
            let half = Int(HoverDetector.circleRadius(width: w, pointSize: pointSize) + 40 * ppp)
            let cx = Int(Double(pointer.x) * Double(w)), cy = Int(Double(pointer.y) * Double(h))
            let x0 = max(cx - half, 0), x1 = min(cx + half + 1, w)
            let y0 = max(cy - half, 0), y1 = min(cy + half + 1, h)
            guard x0 < x1, y0 < y1 else { return nil }
            let pw = x1 - x0, ph = y1 - y0
            let values = [UInt16](unsafeUninitializedCapacity: pw * ph) { out, count in
                var k = 0
                for y in y0 ..< y1 {
                    var px = p + y * row + x0 * 4
                    for _ in 0 ..< pw {
                        out[k] = UInt16(29 * Int(px[0]) + 150 * Int(px[1]) + 77 * Int(px[2]))
                        px += 4
                        k += 1
                    }
                }
                count = pw * ph
            }
            return Patch(x0: x0, y0: y0, width: pw, height: ph, values: values)
        }
    }
}

extension ProjectBundle {
    /// Where a recorded take keeps the screen changes it measured around its clicks.
    public func screenChangesURL(for clip: Clip) -> URL {
        file(clip.screenFile).deletingLastPathComponent().appendingPathComponent(LiveTakeAnalyzer.cacheName)
    }
}
