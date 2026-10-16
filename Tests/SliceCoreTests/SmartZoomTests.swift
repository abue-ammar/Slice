//
//  SmartZoomTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/7/26.
//

import CoreGraphics
@testable import SliceCore
import XCTest

final class SmartZoomTests: XCTestCase {
    static let points = CGSize(width: 1512, height: 982)

    static func log(duration: Double, clicks: [(Double, CGPoint)] = [], scrolls: [Double] = [], typing: [Double] = [],
                    path: (Double) -> CGPoint) -> CursorLog {
        let samples = stride(from: 0.0, through: duration, by: 1.0 / 60).map { t -> CursorLog.Sample in
            let p = path(t)
            return .init(t: t, x: p.x, y: p.y)
        }
        return CursorLog(samples: samples, clicks: clicks.map { .init(t: $0.0, x: $0.1.x, y: $0.1.y) },
                         scrolls: scrolls.map { .init(t: $0, x: 0.5, y: 0.5) }, typing: typing)
    }

    static func move(_ t: Double, _ a: CGPoint, _ b: CGPoint, _ t0: Double, _ t1: Double) -> CGPoint {
        let x = min(max((t - t0) / (t1 - t0), 0), 1)
        let e = x * x * (3 - 2 * x)
        return CGPoint(x: a.x + (b.x - a.x) * e, y: a.y + (b.y - a.y) * e)
    }

    func project(duration: Double, log: CursorLog) -> (Project, [UUID: CursorLog]) {
        var p = Project(name: "Smart")
        p.clips = [Clip(screenFile: "s.mov", cursorFile: "c.json", duration: duration,
                        screenPixelSize: CGSize(width: 3024, height: 1964), captureRect: CGRect(origin: .zero, size: Self.points),
                        cursorInVideo: false)]
        return (p, [p.clips[0].id: log])
    }

    // MARK: Moments

    func testDeliberateClicksScoreAboveFlicks() {
        let a = CGPoint(x: 0.2, y: 0.8), b = CGPoint(x: 0.7, y: 0.3)
        let log = Self.log(duration: 8, clicks: [(3, b), (6.0, Self.move(6.0, b, a, 5.8, 6.2))]) { t in
            t < 5 ? Self.move(t, a, b, 1.5, 2.5) : Self.move(t, b, a, 5.8, 6.2)
        }
        let moments = SmartZoom.interactions(log: log, pointSize: Self.points, duration: 8).moments.filter { $0.kind == .click }
        XCTAssertEqual(moments.count, 2)
        XCTAssertGreaterThan(moments[0].score, AutoZoomSettings().threshold, "landed and paused on it")
        XCTAssertLessThan(moments[1].score, AutoZoomSettings().threshold, "clicked mid-sweep")
    }

    func testTypingAfterAClickHoldsAndScrollingDiscounts() {
        let p = CGPoint(x: 0.4, y: 0.4)
        let log = Self.log(duration: 12, clicks: [(2, p), (2.2, p), (8, p)], scrolls: [7.8, 7.9, 8.1],
                           typing: [2.6, 2.9, 3.3, 3.8]) { _ in p }
        let clicks = SmartZoom.interactions(log: log, pointSize: Self.points, duration: 12).moments.filter { $0.kind == .click }
        XCTAssertEqual(clicks.count, 2, "a double-click counts once")
        XCTAssertTrue(clicks[0].typing)
        XCTAssertEqual(clicks[0].end, 4.0, accuracy: 0.01)
        XCTAssertGreaterThan(clicks[0].score, clicks[1].score + 0.4, "typing lifts it, scrolling sinks the other")
    }

    func testARestAfterMovingSomewhereIsAMoment() {
        let a = CGPoint(x: 0.1, y: 0.1), b = CGPoint(x: 0.6, y: 0.6)
        let log = Self.log(duration: 8, path: { t in Self.move(t, a, b, 1, 2) })
        let pauses = SmartZoom.interactions(log: log, pointSize: Self.points, duration: 8).moments.filter { $0.kind == .pause }
        XCTAssertEqual(pauses.count, 1)
        XCTAssertEqual(pauses[0].t, 2, accuracy: 0.1)
        XCTAssertEqual(Double(pauses[0].point.x), 0.6, accuracy: 0.01)
    }

    // MARK: Planning

    func testRelatedClicksShareOneZoomThatArrivesBeforeThem() {
        let a = CGPoint(x: 0.6, y: 0.5), b = CGPoint(x: 0.66, y: 0.52)
        let log = Self.log(duration: 20, clicks: [(5, a), (6.5, b)]) { t in
            t < 6 ? Self.move(t, CGPoint(x: 0.1, y: 0.9), a, 3, 4) : Self.move(t, a, b, 5.7, 6.1)
        }
        let (project, logs) = project(duration: 20, log: log)
        let detection = [project.clips[0].id: SmartZoom.interactions(log: logs.values.first!, pointSize: Self.points, duration: 20)]
        let blocks = SmartZoom.plan(project: project, detections: detection, settings: AutoZoomSettings())
        XCTAssertEqual(blocks.count, 1)
        let z = blocks[0]
        XCTAssertTrue(z.isAuto)
        XCTAssertLessThanOrEqual(z.start, 5 - project.style.zoomTransitionDuration, "fully zoomed by the first click")
        XCTAssertGreaterThan(z.end, 6.5 + 1, "holds after the last")
        XCTAssertEqual(Double(z.focus.x), 0.63, accuracy: 0.02)
        XCTAssertGreaterThanOrEqual(z.scale, SmartZoom.minScale)
        XCTAssertLessThanOrEqual(z.scale, AutoZoomSettings().targetScale + 1e-9)
    }

    func testIntensityAndSelectivityChangeThePlan() {
        let p = CGPoint(x: 0.5, y: 0.5)
        let moments = [SmartZoom.Moment(kind: .click, t: 4, end: 4, point: p, score: 0.6),
                       SmartZoom.Moment(kind: .click, t: 14, end: 14, point: p, score: 0.9)]
        let (project, _) = project(duration: 20, log: CursorLog())
        let d = [project.clips[0].id: SmartZoom.Detection(moments: moments, scrolls: [])]
        var s = AutoZoomSettings()
        s.selectivity = 0
        XCTAssertEqual(SmartZoom.plan(project: project, detections: d, settings: s).count, 2)
        s.selectivity = 1
        XCTAssertEqual(SmartZoom.plan(project: project, detections: d, settings: s).count, 1, "only the clearest moment")
        s.intensity = 0
        let subtle = SmartZoom.plan(project: project, detections: d, settings: s)[0].scale
        s.intensity = 1
        let strong = SmartZoom.plan(project: project, detections: d, settings: s)[0].scale
        XCTAssertLessThan(subtle, strong)
    }

    func testMomentsFarApartPanInsteadOfZoomingOut() {
        let moments = [SmartZoom.Moment(kind: .click, t: 4, end: 4, point: CGPoint(x: 0.1, y: 0.1), score: 1),
                       SmartZoom.Moment(kind: .click, t: 5.5, end: 5.5, point: CGPoint(x: 0.9, y: 0.9), score: 1)]
        let (project, _) = project(duration: 20, log: CursorLog())
        let blocks = SmartZoom.plan(project: project, detections: [project.clips[0].id: .init(moments: moments, scrolls: [])],
                                    settings: AutoZoomSettings())
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].end, blocks[1].start, "back to back: the camera glides from one view to the next")
        XCTAssertLessThan(blocks[1].start, 5.5)
    }

    func testAPageChangeEndsTheZoomAndScrollingSplitsIt() {
        let p = CGPoint(x: 0.5, y: 0.5)
        var page = SmartZoom.Moment(kind: .click, t: 4, end: 4, point: p, score: 1)
        page.pageChange = true
        let next = SmartZoom.Moment(kind: .click, t: 5, end: 5, point: p, score: 1)
        let (project, _) = project(duration: 30, log: CursorLog())
        let id = project.clips[0].id
        var blocks = SmartZoom.plan(project: project, detections: [id: .init(moments: [page, next], scrolls: [])],
                                    settings: AutoZoomSettings())
        XCTAssertLessThan(blocks[0].end, 5, "zooms out to show the new page")
        let a = SmartZoom.Moment(kind: .click, t: 10, end: 10, point: p, score: 1)
        let b = SmartZoom.Moment(kind: .click, t: 13, end: 13, point: p, score: 1)
        blocks = SmartZoom.plan(project: project, detections: [id: .init(moments: [a, b], scrolls: [TimeSpan(start: 11, end: 11.5)])],
                                settings: AutoZoomSettings())
        XCTAssertEqual(blocks.count, 2)
    }

    func testNothingMeaningfulLeavesTheRecordingAlone() {
        let log = Self.log(duration: 10) { t in CGPoint(x: 0.5 + 0.3 * sin(t * 2), y: 0.5 + 0.3 * cos(t * 1.7)) }
        let (project, logs) = project(duration: 10, log: log)
        let d = [project.clips[0].id: SmartZoom.interactions(log: logs.values.first!, pointSize: Self.points, duration: 10)]
        XCTAssertEqual(SmartZoom.plan(project: project, detections: d, settings: AutoZoomSettings()), [])
    }

    func testZoomStaysWideEnoughForTheCapture() {
        let g = ScreenGeometry(contentSize: CGSize(width: 1400, height: 900), output: CGSize(width: 1400, height: 900), style: FrameStyle())
        XCTAssertLessThan(SmartZoom.pointLimit(g, points: CGSize(width: 700, height: 450)), 1.4)
        XCTAssertGreaterThan(SmartZoom.pointLimit(g, points: CGSize(width: 1728, height: 1117)), 2.5)
        XCTAssertLessThan(SmartZoom.fit(CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.3), g), 1.5)
    }

    // MARK: Video

    func testScreenChangeFindsTheRegionThatReacted() {
        let cols = ScreenChange.columns, rows = ScreenChange.rows
        let before = [UInt8](repeating: 200, count: cols * rows)
        var menu = before
        for y in 13 ..< 30 { for x in 28 ..< 45 { menu[y * cols + x] = 90 } }
        let local = ScreenChange.compare(before, menu, at: CGPoint(x: 0.3, y: 0.2))
        let r = try! XCTUnwrap(local.local)
        XCTAssertEqual(Double(r.minX), 28.0 / Double(cols), accuracy: 0.001)
        XCTAssertEqual(Double(r.minY), 13.0 / Double(rows), accuracy: 0.001)
        let page = [UInt8](repeating: 40, count: cols * rows)
        XCTAssertGreaterThan(ScreenChange.compare(before, page, at: CGPoint(x: 0.3, y: 0.2)).fraction, 0.9)
        XCTAssertNil(ScreenChange.compare(before, page, at: CGPoint(x: 0.3, y: 0.2)).local)
    }

    func testDetectReadsTheVideo() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("smart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, empty) = try ProjectBundle.create(name: "Smart", in: dir)
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: CGSize(width: 1512, height: 982)), duration: 4)
        var project = empty
        project.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", cursorFile: "c.json", duration: 4,
                              screenPixelSize: CGSize(width: 1512, height: 982), captureRect: CGRect(origin: .zero, size: Self.points),
                              cursorInVideo: false)]
        let target = CGPoint(x: 0.5, y: 0.5)
        let log = Self.log(duration: 4, clicks: [(2.5, target)]) { t in Self.move(t, CGPoint(x: 0.1, y: 0.1), target, 1, 1.8) }
        let progress = ProgressBox()
        let found = await SmartZoom.detect(project: project, logs: [id: log], bundle: bundle) { progress.value = $0 }
        let click = try XCTUnwrap(found[id]?.moments.first { $0.kind == .click })
        XCTAssertEqual(click.t, 2.5)
        XCTAssertEqual(progress.value, 1)
    }

    // MARK: Idle cursor

    func testIdlePointerHidesAndComesBackTheMomentItMoves() {
        let a = CGPoint(x: 0.2, y: 0.5), b = CGPoint(x: 0.6, y: 0.5)
        let log = Self.log(duration: 10) { t in t < 6 ? Self.move(t, a, b, 0, 1) : Self.move(t, b, a, 6, 7) }
        var (p, logs) = project(duration: 10, log: log)
        let track = CursorTrack(project: p, logs: logs)
        let out = CGSize(width: 1920, height: 1080)
        func pointer(_ t: Double) -> CursorPointer? { RenderScene(project: p, output: out, cursor: track).pointer(at: t) }
        XCTAssertNotNil(pointer(4), "shown while off")
        p.cursor.hideWhenIdle = true
        p.cursor.idleDelay = 2
        XCTAssertEqual(pointer(2.5)?.opacity, 1)
        XCTAssertLessThan(pointer(3.15)?.opacity ?? 0, 1, "fading after two seconds of rest")
        XCTAssertNil(pointer(4))
        XCTAssertEqual(pointer(6.05)?.opacity, 1, "back as soon as it moves (past sensor jitter)")
        p.cursor.idleDelay = 0.5
        XCTAssertNil(pointer(2))
    }
}

private final class ProgressBox: @unchecked Sendable {
    var value = 0.0
}
