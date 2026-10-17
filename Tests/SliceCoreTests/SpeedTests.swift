//
//  SpeedTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/17/26.
//

import AVFoundation
@testable import SliceCore
import XCTest

final class SpeedTests: XCTestCase {
    func oneClip(_ duration: Double = 20) -> Project {
        var p = Project(name: "S")
        p.clips = [Clip(screenFile: "a", duration: duration, screenPixelSize: CGSize(width: 100, height: 100), captureRect: .zero)]
        return p
    }

    func testSpeedingUpASectionShortensTheEdit() throws {
        var p = oneClip()
        p.split(at: 5)
        p.split(at: 13)
        p.setSpeed(4, for: p.segments[1])
        XCTAssertEqual(p.segments.map(\.speed), [1, 4, 1])
        XCTAssertEqual(p.duration, 5 + 2 + 7, accuracy: 1e-9)
        XCTAssertEqual(p.editedTime(clipIndex: 0, local: 9)!, 6, accuracy: 1e-9)
        XCTAssertEqual(p.editedTime(clipIndex: 0, local: 15)!, 9, accuracy: 1e-9)
        let (ci, local) = try XCTUnwrap(p.sourceTime(edited: 6.5))
        XCTAssertEqual(ci, 0)
        XCTAssertEqual(local, 11, accuracy: 1e-9)
    }

    func testBlocksStayOnTheirMoments() {
        var p = oneClip()
        p.split(at: 5)
        p.split(at: 13)
        p.zoomBlocks = [ZoomBlock(start: 14, end: 16), ZoomBlock(start: 6, end: 10)]
        p.redactions = [RedactBlock(start: 1, end: 3)]
        p.setSpeed(2, for: p.segments[1])
        XCTAssertEqual(p.zoomBlocks[0].start, 10, accuracy: 1e-9)
        XCTAssertEqual(p.zoomBlocks[0].end, 12, accuracy: 1e-9)
        XCTAssertEqual(p.zoomBlocks[1].start, 5.5, accuracy: 1e-9)
        XCTAssertEqual(p.zoomBlocks[1].end, 7.5, accuracy: 1e-9)
        XCTAssertEqual(p.redactions[0].start, 1)
    }

    func testBackToNormalSpeedRemovesTheRange() {
        var p = oneClip()
        p.split(at: 5)
        p.setSpeed(8, for: p.segments[1])
        p.setSpeed(1, for: p.segments[1])
        XCTAssertTrue(p.speeds.isEmpty)
        XCTAssertEqual(p.duration, 20, accuracy: 1e-9)
    }

    func testCuttingInsideASpedUpSectionKeepsItsSpeed() {
        var p = oneClip()
        p.split(at: 4)
        p.setSpeed(2, for: p.segments[1])
        p.removeTime(from: 5, to: 6)
        XCTAssertEqual(p.duration, 4 + 7, accuracy: 1e-9)
        XCTAssertTrue(p.segments.dropFirst().allSatisfy { $0.speed == 2 })
    }

    func testJoiningUnifiesSpeed() throws {
        var p = oneClip()
        p.split(at: 5)
        p.setSpeed(4, for: p.segments[1])
        let join = try XCTUnwrap(p.joins.first { $0.time > 0 && $0.time < p.duration })
        p.heal(join)
        XCTAssertEqual(p.segments.count, 1)
        XCTAssertEqual(p.duration, 20, accuracy: 1e-9)
    }

    func testAutoSpeedsKeepManualOnes() {
        var p = oneClip()
        let id = p.clips[0].id
        p.split(at: 10)
        p.setSpeed(8, for: p.segments[1])
        p.applyAutoSpeeds([SpeedRange(clipID: id, start: 2, end: 6, speed: 4, isAuto: true),
                           SpeedRange(clipID: id, start: 12, end: 16, speed: 4, isAuto: true)])
        XCTAssertEqual(p.speeds.filter(\.isAuto).count, 1)
        XCTAssertEqual(p.duration, 2 + 1 + 4 + 10.0 / 8, accuracy: 1e-9)
        p.clearAutoSpeeds()
        XCTAssertEqual(p.duration, 10 + 10.0 / 8, accuracy: 1e-9)
    }

    func testOldProjectsOpenWithoutSpeeds() throws {
        var p = oneClip()
        p.split(at: 5)
        p.setSpeed(2, for: p.segments[1])
        p.redactions = [RedactBlock(start: 0, end: 1, style: .pixelate)]
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: data), p)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json["speeds"] = nil
        json["redactions"] = nil
        let old = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(old.speeds.isEmpty)
        XCTAssertTrue(old.redactions.isEmpty)
    }

    func testQuietMomentsFindsIdleAndTyping() {
        let p = oneClip(30)
        var log = CursorLog()
        log.samples = stride(from: 0.0, through: 30, by: 1 / 30).map { t in
            t < 4 ? .init(t: t, x: t / 10, y: 0.5) : .init(t: t, x: 0.4, y: 0.5)
        }
        log.typing = Array(stride(from: 18.0, through: 26, by: 0.2))
        let found = QuietMoments.find(project: p, logs: [p.clips[0].id: log], settings: .init())
        let idle = found.filter { $0.speed == 4 }, typing = found.filter { $0.speed == 2 }
        XCTAssertEqual(idle.count, 2)
        XCTAssertEqual(idle[0].start, 4.4, accuracy: 0.3)
        XCTAssertLessThan(idle[0].end, 18)
        XCTAssertEqual(typing.count, 1)
        XCTAssertEqual(typing[0].start, 18.4, accuracy: 0.05)
        XCTAssertEqual(typing[0].end, 25.6, accuracy: 0.05)
    }

    func testSpeechIsNeverSpedUp() {
        var p = oneClip(30)
        p.clips[0].speech = [TimeSpan(start: 0, end: 30)]
        var log = CursorLog()
        log.samples = [.init(t: 0, x: 0.5, y: 0.5), .init(t: 30, x: 0.5, y: 0.5)]
        XCTAssertTrue(QuietMoments.find(project: p, logs: [p.clips[0].id: log], settings: .init()).isEmpty)
    }

    func testCompositionPlaysSpedUpSectionsFaster() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("speed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let (bundle, empty) = try ProjectBundle.create(name: "Speed", in: dir)
        var p = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        let size = CGSize(width: 320, height: 200)
        try await ExportTests.makeMovie(url: clipDir.appendingPathComponent("screen.mov"),
                                        image: RenderTests.fakeScreen(size: size), duration: 4, fps: 30)
        p.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", duration: 4, screenPixelSize: size, captureRect: .zero)]
        p.split(at: 1)
        p.setSpeed(4, for: p.segments[1])
        let state = RenderState(project: p, cursor: CursorTrack(project: p, logs: [:]))
        let built = try await CompositionBuilder.build(project: p, bundle: bundle, state: state, renderSize: size, fps: 30)
        let length = try await built.composition.load(.duration).seconds
        XCTAssertEqual(length, 1.75, accuracy: 0.01)
    }
}
