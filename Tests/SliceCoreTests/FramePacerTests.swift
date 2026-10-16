//
//  FramePacerTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/14/26.
//

import CoreMedia
@testable import SliceCore
import XCTest

final class FramePacerTests: XCTestCase {
    func refreshes(_ hz: Double, count: Int, jitter: Double = 0.0004) -> [Double] {
        (0..<count).map { i in 10 + Double(i) / hz + jitter * sin(Double(i) * 2.399) }
    }

    func kept(_ times: [Double], fps: Int, refresh: Int) -> [Double] {
        var pacer = FramePacer(fps: fps, refreshRate: refresh)
        return times.filter { pacer.offer($0) != .hold }
    }

    func gaps(_ times: [Double]) -> [Double] { zip(times, times.dropFirst()).map { $1 - $0 } }

    func testKeepsEveryRefreshAtTheDisplaysRate() {
        let times = refreshes(60, count: 600)
        XCTAssertEqual(kept(times, fps: 60, refresh: 60), times)
        let fast = refreshes(120, count: 1200)
        XCTAssertEqual(kept(fast, fps: 120, refresh: 120), fast)
    }

    func testBelowTheDisplaysRateKeepsEvenlySpacedFrames() {
        for (fps, refresh) in [(30, 60), (60, 120), (30, 120)] {
            let out = kept(refreshes(Double(refresh), count: 1200), fps: fps, refresh: refresh)
            XCTAssertEqual(out.count, 1200 / (refresh / fps), "\(fps) on \(refresh)")
            for gap in gaps(out) { XCTAssertEqual(gap, 1 / Double(fps), accuracy: 0.001, "\(fps) on \(refresh)") }
        }
    }

    func testARefreshWithNoChangeIsJustAGap() {
        var pacer = FramePacer(fps: 60, refreshRate: 60)
        XCTAssertEqual([0, 1.0 / 60, 3.0 / 60].map { pacer.offer($0) }, [.keep, .keep, .keep])
    }

    func testHeldFrameIsReplacedByOneOnTime() {
        var pacer = FramePacer(fps: 30, refreshRate: 60)
        XCTAssertEqual([0, 1.0 / 60, 2.0 / 60].map { pacer.offer($0) }, [.keep, .hold, .keep])
    }

    func testHeldFrameIsKeptWhenTheScreenThenStaysStill() {
        var pacer = FramePacer(fps: 30, refreshRate: 60)
        XCTAssertEqual([0, 1.0 / 60, 3.0 / 60].map { pacer.offer($0) }, [.keep, .hold, .keepHeldAndThis])
        XCTAssertEqual(pacer.offer(4.0 / 60), .hold)
        XCTAssertEqual(pacer.offer(2), .keepHeldAndThis)
    }

    func testStreamLetsEveryRefreshThrough() {
        XCTAssertEqual(FramePacer.streamInterval(refreshRate: 60), CMTime(value: 1, timescale: 120))
        XCTAssertEqual(FramePacer.streamInterval(refreshRate: 120).seconds, 1.0 / 240, accuracy: 1e-12)
    }
}
