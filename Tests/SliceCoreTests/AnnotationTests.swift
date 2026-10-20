//
//  AnnotationTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/20/26.
//

import CoreGraphics
import CoreImage
@testable import SliceCore
import XCTest

final class AnnotationTests: XCTestCase {
    let red = RGBA(1, 0, 0)

    func stroke(_ times: [Double], end: Double? = nil) -> Annotation {
        Annotation(tool: .pen, color: red, width: 4,
                   points: times.enumerated().map { i, t in .init(t: t, x: 0.2 + Double(i) * 0.1, y: 0.5) }, end: end)
    }

    func testDrawsOnlyWhatWasDrawnByThen() {
        let a = stroke([1, 1.5, 2], end: 5)
        XCTAssertEqual(a.drawnCount(at: 0.9), 0)
        XCTAssertEqual(a.drawnCount(at: 1.6), 2)
        XCTAssertEqual(a.drawnCount(at: 4), 3)
        XCTAssertEqual(a.drawnCount(at: 5), 0, "undone")
    }

    func testTakeTimesStartFromTheTake() {
        XCTAssertNil(stroke([1, 2], end: 3).since(3), "gone before the take began")
        let carried = stroke([1, 2, 4]).since(3)
        XCTAssertEqual(carried?.points.map(\.t), [0, 0, 1], "already drawn when the take began, so there from its start")
        XCTAssertNil(carried?.end)
    }

    func testOlderLogsStillOpen() throws {
        let old = #"{"samples":[],"clicks":[]}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(CursorLog.self, from: old).annotations, [])
        let log = CursorLog(annotations: [stroke([0.5, 1])])
        XCTAssertEqual(try JSONDecoder().decode(CursorLog.self, from: JSONEncoder().encode(log)), log)
    }

    func clipProject(duration: Double = 10, size: CGSize = CGSize(width: 1600, height: 1000)) -> Project {
        var p = Project(name: "Test")
        p.clips = [Clip(screenFile: "s.mov", duration: duration, screenPixelSize: size,
                        captureRect: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))]
        return p
    }

    /// Each logged mark becomes a block from its first point until it was cleared, or the end of the take.
    func testImportedMarksSpanWhenTheyWereOnScreen() {
        var p = clipProject()
        p.cuts = [Cut(clipID: p.clips[0].id, start: 1, end: 2)]
        let log = CursorLog(annotations: [stroke([3, 3.5], end: 6), stroke([8, 8.2]), stroke([0.5], end: 0.52)])
        let blocks = AnnotationBlock.imported(from: log, clipIndex: 0, in: p)
        XCTAssertEqual(blocks.count, 2, "one gone again almost at once is dropped")
        XCTAssertEqual(blocks[0].start, 2, accuracy: 1e-9, "a second earlier: the cut before it")
        XCTAssertEqual(blocks[0].end, 5, accuracy: 1e-9)
        XCTAssertEqual(blocks[0].mark.points.map(\.t), [0, 0.5], "timed from the block's start")
        XCTAssertEqual(blocks[1].end, 9, accuracy: 1e-9, "stays to the end of the take")
        XCTAssertEqual(blocks[0].clipID, p.clips[0].id)
    }

    func testDrawsInOrAppearsWhole() {
        var b = AnnotationBlock(start: 2, end: 6, mark: stroke([0, 0.5, 1]))
        XCTAssertEqual(b.drawnCount(at: 2.6), 2)
        XCTAssertEqual(b.drawnCount(at: 6), 0)
        b.drawsIn = false
        XCTAssertEqual(b.drawnCount(at: 2), 3)
    }

    func testMovingAndResizingKeepsTheShape() {
        var b = AnnotationBlock(start: 0, end: 1, mark: stroke([0, 1, 2]))
        let screen = CGSize(width: 1000, height: 500)
        XCTAssertEqual(b.bounds(screenPoints: screen), CGRect(x: 0.2, y: 0.5, width: 0.2, height: 0))
        b.fit(to: CGRect(x: 0.5, y: 0.6, width: 0.4, height: 0), screenPoints: screen)
        for (x, want) in zip(b.mark.points.map(\.x), [0.5, 0.7, 0.9]) { XCTAssertEqual(x, want, accuracy: 1e-9) }
        XCTAssertEqual(b.mark.points.map(\.y), [0.6, 0.6, 0.6])
    }

    /// A box drawn over the top-left quarter shows there in the frame, at its time, and nowhere else apart from the top-left position..
    func testMarksLandWhereAndWhenTheyWereDrawn() throws {
        let size = CGSize(width: 1600, height: 1000)
        var p = clipProject(size: size)
        let box = Annotation(tool: .rectangle, color: red, width: 6,
                             points: [.init(t: 2, x: 0.1, y: 0.1), .init(t: 2.5, x: 0.4, y: 0.4)], end: 6)
        p.annotations = AnnotationBlock.imported(from: CursorLog(annotations: [box]), clipIndex: 0, in: p)
        let scene = RenderScene(project: p, output: CGSize(width: 1920, height: 1080), cursor: CursorTrack(project: p, logs: [:]))
        let renderer = FrameRenderer()
        let screen = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(origin: .zero, size: size))
        func pixel(at t: Double, _ x: CGFloat, _ y: CGFloat) -> [UInt8] {
            var px = [UInt8](repeating: 0, count: 4)
            renderer.context.render(renderer.annotated(screen, scene: scene, time: t), toBitmap: &px, rowBytes: 4,
                                    bounds: CGRect(x: x, y: size.height - y - 1, width: 1, height: 1), format: .RGBA8,
                                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return px
        }
        let edge = (x: size.width * 0.1, y: size.height * 0.25)
        XCTAssertEqual(pixel(at: 1, edge.x, edge.y), [255, 255, 255, 255], "not drawn yet")
        XCTAssertEqual(pixel(at: 3, edge.x, edge.y), [255, 0, 0, 255])
        XCTAssertEqual(pixel(at: 3, size.width * 0.25, size.height * 0.25), [255, 255, 255, 255], "hollow")
        XCTAssertEqual(pixel(at: 3, size.width * 0.7, size.height * 0.7), [255, 255, 255, 255])
        XCTAssertEqual(pixel(at: 7, edge.x, edge.y), [255, 255, 255, 255], "cleared")
        p.annotations[0].mark.color = RGBA(0, 0, 1)
        let recoloured = RenderScene(project: p, output: CGSize(width: 1920, height: 1080), cursor: CursorTrack(project: p, logs: [:]))
        var px = [UInt8](repeating: 0, count: 4)
        renderer.context.render(renderer.annotated(screen, scene: recoloured, time: 3), toBitmap: &px, rowBytes: 4,
                                bounds: CGRect(x: edge.x, y: size.height - edge.y - 1, width: 1, height: 1), format: .RGBA8,
                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        XCTAssertEqual(px, [0, 0, 255, 255], "an edit shows at once, not the kept drawing of the old one")
    }

    /// The preview draws marks with only the pixels it shows, and draws an unchanged mark once, an edit draws it again.
    func testPreviewDrawsMarksSmallAndOnce() {
        let size = CGSize(width: 3024, height: 1964)
        var p = clipProject(size: size)
        p.annotations = [AnnotationBlock(start: 0, end: 5, mark: Annotation(tool: .pen, color: red, width: 4,
                                                                             points: [.init(t: 0, x: 0.2, y: 0.2), .init(t: 0, x: 0.6, y: 0.5)]))]
        let renderer = FrameRenderer()
        let screen = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: CGRect(origin: .zero, size: size))
        let preview = RenderScene(project: p, output: CGSize(width: 1280, height: 720), cursor: CursorTrack(project: p, logs: [:]))
        XCTAssertLessThan(renderer.annotationRasterScale(scene: preview, time: 1, screen: screen.extent), 0.6)
        let export = RenderScene(project: p, output: CGSize(width: 3840, height: 2160), cursor: CursorTrack(project: p, logs: [:]))
        XCTAssertEqual(renderer.annotationRasterScale(scene: export, time: 1, screen: screen.extent), 1)

        _ = renderer.annotated(screen, scene: preview, time: 1)
        let r = renderer.annotationRasterScale(scene: preview, time: 1, screen: screen.extent)
        XCTAssertNotNil(renderer.annotationMarks.image(for: p.annotations[0].mark, screen: size, scale: r), "kept after the first frame")
        var moved = p.annotations[0].mark
        moved.points[0].x = 0.25
        XCTAssertNil(renderer.annotationMarks.image(for: moved, screen: size, scale: r), "an edited mark is drawn again")
    }
}
