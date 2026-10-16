//
//  PreviewFramesTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/8/26.
//

import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

@MainActor
final class PreviewFramesTests: XCTestCase {
    let size = CGSize(width: 640, height: 400)
    let duration = 3.0
    let fps = 30

    private func player() async throws -> (AVPlayer, AVPlayerItemVideoOutput, PreviewPacking, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(UUID().uuidString)")
        let (bundle, empty) = try ProjectBundle.create(name: "Preview", in: dir)
        var p = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: size), duration: duration, fps: fps)
        p.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", duration: duration, screenPixelSize: size, captureRect: .zero)]
        let state = RenderState(project: p, cursor: CursorTrack(project: p, logs: [:]))
        let built = try await CompositionBuilder.build(project: p, bundle: bundle, state: state, renderSize: .zero, fps: 60,
                                                       preview: true)
        let item = AVPlayerItem(asset: built.composition)
        item.videoComposition = built.videoComposition
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        item.add(output)
        return (AVPlayer(playerItem: item), output, try XCTUnwrap(built.packing), dir)
    }

    private func shownTime(_ buffer: CVPixelBuffer, packing: PreviewPacking) -> Double? {
        let screen = packing.unpack(CIImage(cvPixelBuffer: buffer), clip: 0, hasCamera: false).screen!
        let width = Int(screen.extent.width)
        var row = [UInt8](repeating: 0, count: width * 4)
        CIContext().render(screen, toBitmap: &row, rowBytes: width * 4, bounds: CGRect(x: 0, y: 2, width: CGFloat(width), height: 1),
                           format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        guard let x = (0 ..< width).first(where: { row[$0 * 4] > 200 && row[$0 * 4 + 1] < 80 }) else { return nil }
        let frames = Double(duration) * Double(fps)
        return (Double(x) / Double(width) * frames).rounded() / Double(fps)
    }

    func testPausedSeeksDeliverTheFrameForThatTime() async throws {
        let (player, output, packing, dir) = try await player()
        defer { try? FileManager.default.removeItem(at: dir) }
        for target in [1.5, 0.5, 2.25] {
            await player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            var buffer: CVPixelBuffer?
            for _ in 0 ..< 200 {
                let t = player.currentTime()
                if output.hasNewPixelBuffer(forItemTime: t) { buffer = output.copyPixelBuffer(forItemTime: t, itemTimeForDisplay: nil) }
                if buffer != nil { break }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            let shown = try XCTUnwrap(buffer.flatMap { shownTime($0, packing: packing) }, "frame for \(target)")
            XCTAssertEqual(shown, target, accuracy: 1.0 / Double(fps) + 0.001)
        }
    }

    func testPlaybackFramesMatchThePlayhead() async throws {
        let (player, output, packing, dir) = try await player()
        defer { try? FileManager.default.removeItem(at: dir) }
        player.play()
        var errors: [Double] = []
        for _ in 0 ..< 150 {
            let now = output.itemTime(forHostTime: CACurrentMediaTime())
            if output.hasNewPixelBuffer(forItemTime: now), let b = output.copyPixelBuffer(forItemTime: now, itemTimeForDisplay: nil),
               now.seconds > 0.2, now.seconds < duration - 0.2, let shown = shownTime(b, packing: packing) {
                errors.append(shown - now.seconds)
            }
            try await Task.sleep(nanoseconds: 8_000_000)
        }
        player.pause()
        XCTAssertGreaterThan(errors.count, 20)
        XCTAssertLessThanOrEqual(errors.max() ?? 1, 0.002)
        XCTAssertGreaterThanOrEqual(errors.min() ?? -1, -(1.0 / Double(fps) + 0.02))
    }
}
