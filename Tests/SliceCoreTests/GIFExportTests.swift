//
//  GIFExportTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/17/26.
//

import AVFoundation
import ImageIO
@testable import SliceCore
import XCTest

final class GIFExportTests: XCTestCase {
    func testEncoderRoundTrip() throws {
        let w = 64, h = 48, frames = 10
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("encoder-\(UUID().uuidString).gif")
        defer { try? FileManager.default.removeItem(at: url) }
        let encoder = try GIFEncoder(url: url, width: w, height: h)
        var sources: [[UInt8]] = []
        for f in 0 ..< frames {
            var px = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0 ..< h {
                for x in 0 ..< w {
                    let i = (y * w + x) * 4
                    let box = x >= f * 4 && x < f * 4 + 12 && y >= 10 && y < 30
                    px[i] = box ? 40 : UInt8(x * 4)
                    px[i + 1] = box ? 200 : UInt8(y * 5)
                    px[i + 2] = box ? 250 : 255
                    px[i + 3] = 255
                }
            }
            if f != 5 { sources.append(px) } else { sources.append(sources[4]) }
            try sources[f].withUnsafeBytes { try encoder.add(bgra: $0.baseAddress!, bytesPerRow: w * 4, time: Double(f) / 10) }
        }
        try encoder.finish(duration: Double(frames) / 10)

        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        // Frame 5 repeats frame 4, so it's folded into frame 4's delay.
        XCTAssertEqual(CGImageSourceGetCount(source), frames - 1)
        var total = 0.0
        for i in 0 ..< CGImageSourceGetCount(source) {
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        }
        XCTAssertEqual(total, 1, accuracy: 0.001)

        let last = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, CGImageSourceGetCount(source) - 1, nil))
        var decoded = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &decoded, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        ctx.draw(last, in: CGRect(x: 0, y: 0, width: w, height: h))
        let expected = sources[frames - 1]
        var error = 0
        for i in stride(from: 0, to: expected.count, by: 4) {
            for c in 0 ..< 3 { error += abs(Int(expected[i + c]) - Int(decoded[i + c])) }
        }
        XCTAssertLessThan(Double(error) / Double(w * h * 3), 3)
    }

    func testGIFExport() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("gif-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, empty) = try ProjectBundle.create(name: "GIF", in: dir)
        var project = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: CGSize(width: 1512, height: 982)), duration: 2)
        project.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", duration: 2,
                              screenPixelSize: CGSize(width: 1512, height: 982), captureRect: .zero)]
        project.export.format = .gif
        project.export.aspect = .landscape16x9
        project.export.gifSize = .small
        project.export.gifFPS = 15
        try bundle.save(project)
        XCTAssertEqual(try bundle.load().export, project.export)
        XCTAssertEqual(project.exportSize, CGSize(width: 640, height: 360))

        let out = dir.appendingPathComponent("out.gif")
        try await Exporter.export(project: project, bundle: bundle, cursor: CursorTrack(project: project, logs: [:]),
                                  to: out, progress: { _ in })
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(out as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetStatus(source), .statusComplete)
        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        XCTAssertEqual(props?[kCGImagePropertyPixelWidth] as? Int, 640)
        XCTAssertEqual(props?[kCGImagePropertyPixelHeight] as? Int, 360)
        var total = 0.0
        for i in 0 ..< CGImageSourceGetCount(source) {
            let p = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = p?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            total += gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double ?? 0
        }
        XCTAssertEqual(total, 2, accuracy: 0.05)
        XCTAssertLessThanOrEqual(CGImageSourceGetCount(source), 30)
    }
}
