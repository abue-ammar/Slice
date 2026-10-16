//
//  TransitionTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/1/26.
//

import AVFoundation
import CoreImage
@testable import SliceCore
import XCTest

final class TransitionTests: XCTestCase {
    func splitProject() -> Project {
        var p = Project(name: "T")
        p.clips = [Clip(screenFile: "a", duration: 10, screenPixelSize: CGSize(width: 100, height: 100), captureRect: .zero),
                   Clip(screenFile: "b", duration: 5, screenPixelSize: CGSize(width: 100, height: 100), captureRect: .zero)]
        p.split(at: 4)
        return p
    }

    func testPlacedAtSplitsAndBetweenTakes() {
        var p = splitProject()
        let segs = p.segments
        XCTAssertEqual(segs.count, 3)
        p.setTransition(into: segs[1], kind: .zoomBlur)
        p.setTransition(into: segs[2], kind: .pageCurl)
        let placed = p.placedTransitions
        XCTAssertEqual(placed.map(\.window.time), [4, 10])
        XCTAssertEqual(placed[0].duration, ClipTransition.Kind.zoomBlur.defaultDuration, accuracy: 1e-9)
        XCTAssertEqual(p.duration, 15, "Transitions don't change the edit's length")

        let (active, progress) = try! XCTUnwrap(placed.active(at: 4))
        XCTAssertEqual(active.transition.kind, .zoomBlur)
        XCTAssertEqual(progress, 0.5, accuracy: 1e-9)
        XCTAssertNil(placed.active(at: 3))

        let id = placed[0].transition.id
        p.setTransition(into: segs[1], kind: .snap)
        XCTAssertEqual(p.transitions.count, 2)
        XCTAssertEqual(p.transition(into: segs[1])?.id, id)
        XCTAssertEqual(p.transition(into: segs[1])?.duration, ClipTransition.Kind.snap.defaultDuration)
    }

    func testShortSectionsShortenTransitions() {
        var p = splitProject()
        p.split(at: 4.6)
        let segs = p.segments
        p.setTransition(into: segs[1], kind: .zoomBlur)
        p.setTransition(into: segs[2], kind: .zoomBlur)
        p.transitions = p.transitions.map { var t = $0; t.duration = 2; return t }
        let placed = p.placedTransitions
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(placed[0].duration, 0.6, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(placed[0].end, placed[1].start + 1e-9)
    }

    func testTrimAndOrphans() {
        var p = splitProject()
        p.setTransition(into: p.segments[1], kind: .revolve)
        p.trim(segment: p.segments[1], newStart: 5)
        XCTAssertEqual(p.placedTransitions.count, 1, "Follows the section's new start")
        XCTAssertEqual(p.placedTransitions[0].window.time, 4, accuracy: 1e-9)

        p.delete(segment: p.segments[1])
        XCTAssertTrue(p.placedTransitions.filter { $0.transition.kind == .revolve }.isEmpty)
    }

    func testSavedWithProject() throws {
        var p = splitProject()
        p.setTransition(into: p.segments[1], kind: .burn)
        let data = try JSONEncoder().encode(p)
        XCTAssertEqual(try JSONDecoder().decode(Project.self, from: data), p)
        var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        json["transitions"] = nil
        let old = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(old.transitions, [])
        var older = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var saved = (older["transitions"] as! [[String: Any]])[0]
        saved["kind"] = "crossDissolve"
        saved["direction"] = "left"
        older["transitions"] = [saved]
        let reopened = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: older))
        XCTAssertEqual(reopened.transitions.first?.kind, .zoomBlur)
    }

    func testEveryKindRunsFromOutgoingToIncoming() throws {
        for kind in ClipTransition.Kind.allCases {
            XCTAssertNotNil(FrameRenderer.transitionKernels?[kind.kernel], "\(kind) compiled")
        }
        let size = CGSize(width: 160, height: 90)
        let frame = CGRect(origin: .zero, size: size)
        let red = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: frame)
        let blue = CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: frame)
        let ctx = CIContext()
        func centre(_ image: CIImage) -> (r: Double, b: Double) {
            var px = [UInt8](repeating: 0, count: 4)
            ctx.render(image, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 80, y: 45, width: 1, height: 1),
                       format: .RGBA8, colorSpace: nil)
            return (Double(px[0]) / 255, Double(px[2]) / 255)
        }
        for kind in ClipTransition.Kind.allCases {
            let tr = ClipTransition(clipID: UUID(), time: 0, kind: kind)
            let start = FrameRenderer.blend(from: red, to: blue, transition: tr, progress: 0, size: size)
            let end = FrameRenderer.blend(from: red, to: blue, transition: tr, progress: 0.9999, size: size)
            XCTAssertEqual(start.extent, frame, "\(kind)")
            XCTAssertGreaterThan(centre(start).r, 0.9, "\(kind) starts on the outgoing frame")
            XCTAssertGreaterThan(centre(end).b, 0.9, "\(kind) ends on the incoming frame")
        }
        func bytes(_ kind: ClipTransition.Kind) -> [UInt8] {
            let image = FrameRenderer.blend(from: red, to: blue, transition: ClipTransition(clipID: UUID(), time: 0, kind: kind),
                                            progress: 0.45, size: size)
            var px = [UInt8](repeating: 0, count: 160 * 90 * 4)
            ctx.render(image, toBitmap: &px, rowBytes: 160 * 4, bounds: frame, format: .RGBA8, colorSpace: nil)
            return px
        }
        XCTAssertEqual(Set(ClipTransition.Kind.allCases.map(bytes)).count, ClipTransition.Kind.allCases.count)
    }

    func testExportDissolvesBetweenTakes() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("transition-test-\(UUID().uuidString)")
        let (bundle, empty) = try ProjectBundle.create(name: "Transition", in: dir)
        var project = empty
        let size = CGSize(width: 640, height: 360)
        let a = UUID(), b = UUID()
        let (dirA, relA) = try bundle.makeClipFolder(id: a)
        let (dirB, relB) = try bundle.makeClipFolder(id: b)
        try await ExportTests.makeMovie(url: dirA.appendingPathComponent("screen.mov"),
                                        image: CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size)),
                                        duration: 3)
        try await ExportTests.makeMovie(url: dirB.appendingPathComponent("screen.mov"),
                                        image: CIImage(color: CIColor(red: 0, green: 0, blue: 1)).cropped(to: CGRect(origin: .zero, size: size)),
                                        duration: 2)
        project.clips = [
            Clip(id: a, screenFile: "\(relA)/screen.mov", duration: 3, screenPixelSize: size, captureRect: .zero),
            Clip(id: b, screenFile: "\(relB)/screen.mov", duration: 2, screenPixelSize: size, captureRect: .zero),
        ]
        project.export.resolution = .p1080
        project.export.fps = 30
        let id = project.setTransition(into: project.segments[1], kind: .zoomBlur)
        project.transitions[0].duration = 1
        XCTAssertEqual(project.transitions[0].id, id)
        try bundle.save(project)
        XCTAssertEqual(try bundle.load(), project)

        let out = dir.appendingPathComponent("out.mp4")
        try await Exporter.export(project: project, bundle: bundle, cursor: CursorTrack(project: project, logs: [:]),
                                  to: out, progress: { _ in })
        let asset = AVURLAsset(url: out)
        let duration = try await asset.load(.duration).seconds
        XCTAssertEqual(duration, 5, accuracy: 0.1)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        func centre(at t: Double) async throws -> (r: Double, b: Double) {
            let image = try await generator.image(at: CMTime(seconds: t, preferredTimescale: 600)).image
            let ci = CIImage(cgImage: image)
            var px = [UInt8](repeating: 0, count: 4)
            CIContext().render(ci, toBitmap: &px, rowBytes: 4,
                               bounds: CGRect(x: ci.extent.midX, y: ci.extent.midY, width: 1, height: 1), format: .RGBA8,
                               colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
            return (Double(px[0]) / 255, Double(px[2]) / 255)
        }
        let before = try await centre(at: 2.3)
        let middle = try await centre(at: 3.0)
        let after = try await centre(at: 3.7)
        XCTAssertGreaterThan(before.r, 0.8)
        XCTAssertLessThan(before.b, 0.2)
        XCTAssertGreaterThan(middle.r, 0.25, "Mid-dissolve shows both takes")
        XCTAssertGreaterThan(middle.b, 0.25, "Mid-dissolve shows both takes")
        XCTAssertGreaterThan(after.b, 0.8)
        XCTAssertLessThan(after.r, 0.2)
        try? FileManager.default.removeItem(at: dir)
    }
}
