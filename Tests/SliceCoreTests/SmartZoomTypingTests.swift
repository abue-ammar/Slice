//
//  SmartZoomTypingTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/17/26.
//

import AppKit
import AVFoundation
import CoreGraphics
@testable import SliceCore
import XCTest

final class SmartZoomTypingTests: XCTestCase {
    let cols = ScreenChange.columns, rows = ScreenChange.rows

    /// A blank screen with `typed` cells of text on row 30 from column 20, and a menu-bar clock that ticks every frame.
    func screen(typed: Int, tick: Int) -> [UInt8] {
        var g = [UInt8](repeating: 220, count: cols * rows)
        for x in 20 ..< 20 + typed { g[30 * cols + x] = 60 }
        for x in 90 ..< 94 { g[x] = UInt8(100 + (tick % 2) * 100) }
        return g
    }

    func testTypedAreaFollowsTheTextNotTheClock() throws {
        let before = screen(typed: 0, tick: 0)
        let during = (1 ... 6).map { screen(typed: $0 * 6, tick: $0) }
        let caret = CGPoint(x: 20.5 / Double(cols), y: 30.5 / Double(rows))
        let area = try XCTUnwrap(SmartZoom.typedArea(before: before, during: during, caret: caret))
        XCTAssertEqual(Double(area.minX), 20.0 / Double(cols), accuracy: 1e-6)
        XCTAssertEqual(Double(area.maxX), 56.0 / Double(cols), accuracy: 1e-6, "reaches the last thing typed")
        XCTAssertGreaterThan(Double(area.minY), 0.4, "the clock isn't part of it")
        let found = try XCTUnwrap(SmartZoom.typedArea(before: before, during: during, caret: nil), "finds the caret itself")
        XCTAssertEqual(found, area)
    }

    func testAPageChangeStopsTheMeasurement() throws {
        let before = screen(typed: 0, tick: 0)
        let page = [UInt8](repeating: 20, count: cols * rows)
        let area = try XCTUnwrap(SmartZoom.typedArea(before: before, during: [screen(typed: 8, tick: 0), page, page],
                                                     caret: CGPoint(x: 0.21, y: 0.51)))
        XCTAssertEqual(Double(area.maxX), 28.0 / Double(cols), accuracy: 1e-6)
    }

    func testLoneTypingBecomesAMoment() {
        let p = CGPoint(x: 0.5, y: 0.5)
        let log = SmartZoomTests.log(duration: 12, typing: Array(stride(from: 2.0, through: 4.5, by: 0.25)) + [8, 8.3]) { _ in p }
        let moments = SmartZoom.interactions(log: log, pointSize: SmartZoomTests.points, duration: 12).moments
        let typing = moments.filter { $0.kind == .typing }
        XCTAssertEqual(typing.count, 1, "the short burst at 8 s is too brief")
        XCTAssertEqual(typing[0].typingStart, 2)
        XCTAssertEqual(typing[0].end, 4.7, accuracy: 1e-9)
        let samples = SmartZoom.typingSamples(moments, duration: 12)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples[0].before, 1.85, accuracy: 1e-9)
        XCTAssertEqual(samples[0].during.last!, 4.6, accuracy: 1e-9, "just after the last key")
    }

    func plan(_ m: SmartZoom.Moment) -> (ZoomBlock, ScreenGeometry, Project) {
        var p = Project(name: "T")
        p.clips = [Clip(screenFile: "s", cursorFile: "c", duration: 20, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: CGRect(origin: .zero, size: SmartZoomTests.points), cursorInVideo: false)]
        let blocks = SmartZoom.plan(project: p, detections: [p.clips[0].id: .init(moments: [m], scrolls: [])], settings: AutoZoomSettings())
        let g = ScreenGeometry(contentSize: CGSize(width: 3024, height: 1964), output: p.outputSize(shortSide: 1080), style: p.style)
        return (blocks[0], g, p)
    }

    func onScreen(_ r: CGRect, _ g: ScreenGeometry) -> CGRect {
        let c = g.contentRect
        return CGRect(x: c.minX + r.minX * c.width, y: c.minY + r.minY * c.height, width: r.width * c.width, height: r.height * c.height)
    }

    func testTypingZoomShowsWhatWasTyped() {
        var m = SmartZoom.Moment(kind: .click, t: 4, end: 8, point: CGPoint(x: 0.2, y: 0.5), score: 1)
        m.typing = true
        m.typingStart = 4.5
        m.typed = CGRect(x: 0.2, y: 0.48, width: 0.3, height: 0.05)
        let (block, g, _) = plan(m)
        XCTAssertNil(block.endFocus)
        let view = g.zoomedView(scale: block.scale, focus: block.focus)
        XCTAssertTrue(view.insetBy(dx: -0.5, dy: -0.5).contains(onScreen(m.typed!, g)), "the whole line is in view, not just the click")
        XCTAssertGreaterThanOrEqual(block.scale, SmartZoom.minScale)
    }

    func testLongTypingPansAlongTheLine() {
        var m = SmartZoom.Moment(kind: .typing, t: 4, end: 12, point: CGPoint(x: 0.5, y: 0.3), score: 1)
        m.typing = true
        m.typingStart = 4
        m.typed = CGRect(x: 0.05, y: 0.28, width: 0.88, height: 0.04)
        let (block, g, _) = plan(m)
        let end = try! XCTUnwrap(block.endFocus)
        XCTAssertLessThan(block.focus.x, end.x, "starts where the typing starts and moves with it")
        XCTAssertGreaterThanOrEqual(block.scale, SmartZoom.minScale)
        let first = g.zoomedView(scale: block.scale, focus: block.focus), last = g.zoomedView(scale: block.scale, focus: end)
        let line = onScreen(m.typed!, g)
        XCTAssertLessThanOrEqual(first.minX, line.minX + 0.5)
        XCTAssertGreaterThanOrEqual(last.maxX, line.maxX - 0.5)
        XCTAssertTrue(first.minY <= line.minY && first.maxY >= line.maxY)
    }

    /// A Retina-sized screen where a line of 13 pt text is typed out between 1 s and 3.5 s.
    static func makeTypingMovie(url: URL, size: CGSize, fps: Int = 10) async throws {
        let text = "Searching for the quick brown fox that jumps over the lazy dog" as NSString
        let origin = NSPoint(x: size.width * 0.3, y: size.height * 0.4)
        func frame(_ t: Double) -> CGImage {
            let shown = Int(Double(text.length) * min(max((t - 1) / 2.5, 0), 1))
            let img = NSImage(size: size, flipped: true) { rect in
                NSColor.white.setFill()
                rect.fill()
                NSColor(white: 0.93, alpha: 1).setFill()
                NSRect(x: 0, y: 0, width: size.width, height: size.height * 0.05).fill()
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black]
                text.substring(to: shown).draw(at: origin, withAttributes: attrs)
                return true
            }
            var r = NSRect(origin: .zero, size: size)
            return img.cgImage(forProposedRect: &r, context: nil, hints: [.ctm: AffineTransform.identity])!
        }
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.hevc, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        let ctx = CIContext()
        for i in 0 ..< 5 * fps {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
            ctx.render(CIImage(cgImage: frame(Double(i) / Double(fps))), to: pb!)
            adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: CMTimeScale(fps)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        if let e = writer.error { throw e }
    }

    func testFindsRealTypedTextInTheVideo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("typed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, empty) = try ProjectBundle.create(name: "Typed", in: dir)
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        let size = CGSize(width: 3024, height: 1964)
        try await Self.makeTypingMovie(url: clipDir.appendingPathComponent("screen.mov"), size: size)
        var project = empty
        project.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", cursorFile: "c.json", duration: 5, screenPixelSize: size,
                              captureRect: CGRect(origin: .zero, size: SmartZoomTests.points), cursorInVideo: false)]
        let log = SmartZoomTests.log(duration: 5, typing: Array(stride(from: 1.0, through: 3.5, by: 0.15))) { _ in
            CGPoint(x: 0.85, y: 0.85)
        }
        let found = await SmartZoom.detect(project: project, logs: [id: log], bundle: bundle)
        let typing = try XCTUnwrap(found[id]?.moments.first { $0.kind == .typing })
        let typed = try XCTUnwrap(typing.typed, "the line being typed was found")
        XCTAssertEqual(Double(typed.minX), 0.3, accuracy: 0.03)
        XCTAssertEqual(Double(typed.maxX), 0.528, accuracy: 0.02, "reaches the end of the line")
        XCTAssertEqual(Double(typed.midY), 0.41, accuracy: 0.04)
        XCTAssertGreaterThan(typing.score, AutoZoomSettings().threshold)
        let blocks = SmartZoom.plan(project: project, detections: found, settings: AutoZoomSettings())
        XCTAssertEqual(blocks.count, 1)
        XCTAssertGreaterThan(Double(blocks[0].endFocus?.x ?? blocks[0].focus.x), 0.4, "aimed at the text, not where the pointer sits")
    }

    func testLoneTypingThatCantBeFoundIsDropped() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("typing-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, empty) = try ProjectBundle.create(name: "Typing", in: dir)
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: CGSize(width: 756, height: 491)), duration: 5)
        var project = empty
        project.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", cursorFile: "c.json", duration: 5,
                              screenPixelSize: CGSize(width: 756, height: 491), captureRect: CGRect(origin: .zero, size: SmartZoomTests.points),
                              cursorInVideo: false)]
        let log = SmartZoomTests.log(duration: 5, typing: Array(stride(from: 1.0, through: 3.5, by: 0.2))) { _ in CGPoint(x: 0.5, y: 0.5) }
        let found = await SmartZoom.detect(project: project, logs: [id: log], bundle: bundle)
        let typing = try XCTUnwrap(found[id]?.moments.first { $0.kind == .typing })
        XCTAssertNil(typing.typed, "nothing changed on this screen")
        XCTAssertLessThan(typing.score, AutoZoomSettings().threshold)
    }
}
