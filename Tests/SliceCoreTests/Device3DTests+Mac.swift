//
//  Device3DTests+Mac.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/21/26.
//

import CoreImage
import Metal
import SceneKit
@testable import SliceCore
import XCTest

/// The 3D MacBook, for screen recordings.
final class Device3DMacTests: XCTestCase {
    static let canvas = CGSize(width: 1512, height: 982)

    /// A screen: green over magenta, with a white bar down its left so a mirrored picture would show.
    static let screen: CIImage = {
        let whole = CGRect(origin: .zero, size: canvas)
        return CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 120, height: canvas.height))
            .composited(over: CIImage(color: Device3DTests.green).cropped(to: CGRect(x: 0, y: canvas.height / 2, width: canvas.width,
                                                                                      height: canvas.height / 2)))
            .composited(over: CIImage(color: Device3DTests.magenta).cropped(to: whole))
    }()

    static func screenProject() -> Project {
        var p = Project(name: "Mac")
        p.clips = [Clip(screenFile: "s.mov", duration: 10, screenPixelSize: canvas, captureRect: CGRect(origin: .zero, size: canvas))]
        p.device3D.enabled = true
        p.device3D.model = .macBookNeo
        p.device3D.finish = .yellow
        p.device3D.placement = Device3DPlacement(yaw: 0, pitch: 0)
        p.device3D.background = .color
        p.device3D.shadowOpacity = 0
        return p
    }

    let renderer = FrameRenderer()

    func pixels(_ image: CIImage, size: CGSize) -> (Int, Int) -> (r: Double, g: Double, b: Double) {
        let cg = renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: size), format: .RGBA8,
                                                colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
        let data = cg.dataProvider!.data! as Data
        let row = cg.bytesPerRow
        return { x, y in
            let o = y * row + x * 4
            return (Double(data[o]) / 255, Double(data[o + 1]) / 255, Double(data[o + 2]) / 255)
        }
    }

    func render(_ p: Project, output: CGSize) -> CIImage {
        let scene = RenderScene(project: p, output: output, cursor: CursorTrack(project: p, logs: [:]))
        return renderer.render(scene: scene, time: 1, screen: Self.screen, camera: nil)
    }

    func template(_ m: Device3DModel = .macBookNeo) throws -> Device3DTemplate {
        let url = try XCTUnwrap(Bundle.module.url(forResource: m.resource, withExtension: "usdz", subdirectory: "Models"))
        return try Device3DTemplate(url: url, name: m.label, displayNode: m.displayNode, bodyColor: m.bodyColor,
                                    bodyMaterials: m.bodyMaterials, laptop: true)
    }

    /// Pixels showing the recording (its green or magenta), sampled every few pixels.
    func screenShown(_ px: (Int, Int) -> (r: Double, g: Double, b: Double), size: CGSize) -> Int {
        var count = 0
        for y in stride(from: 0, to: Int(size.height), by: 4) {
            for x in stride(from: 0, to: Int(size.width), by: 4) {
                let q = px(x, y)
                if (q.g > 0.6 && q.r < 0.35) || (q.r > 0.7 && q.b > 0.55 && q.g < 0.25) { count += 1 }
            }
        }
        return count
    }

    func testMacBookLoadsWithItsScreenSetInItsBezel() throws {
        XCTAssertEqual(Device3DModel.macBookNeo.kind, .laptop)
        XCTAssertEqual(Device3DRenderer.shared.status(for: .macBookNeo), .ready(hasDisplayMesh: true))
        let aspect = try XCTUnwrap(Device3DRenderer.shared.displayAspect(for: .macBookNeo))
        XCTAssertEqual(aspect, 1.56, accuracy: 0.06, "the screen inside the bezel, a MacBook's shape")
        let t = try template()
        let region = try XCTUnwrap(t.screenRegion, "the screen is found within the lid")
        XCTAssertGreaterThan(region.width, 0.85)
        XCTAssertLessThan(region.width, 0.99)
        XCTAssertNotNil(t.screenMask)
        XCTAssertGreaterThan(t.size.x, t.size.y, "a laptop is wider than it is tall")
        XCTAssertGreaterThan(t.size.z, 0.5, "and has its base reaching out in front")
    }

    func testScreenRecordingIsDrawnUprightOnTheMacBook() throws {
        let out = CGSize(width: 1920, height: 1080)
        let image = render(Self.screenProject(), output: out)
        let px = pixels(image, size: out)
        func magenta(_ q: (r: Double, g: Double, b: Double)) -> Bool { abs(q.r - 0.85) < 0.12 && abs(q.g - 0.1) < 0.12 && abs(q.b - 0.7) < 0.12 }
        func green(_ q: (r: Double, g: Double, b: Double)) -> Bool { q.g > 0.6 && q.r < 0.35 }
        // The screen's lower half down the middle of the frame, then across it: magenta, the white bar at its left.
        let rows = (0 ..< 1080).filter { magenta(px(960, $0)) }
        let row = try XCTUnwrap(rows.isEmpty ? nil : rows[rows.count / 2], "the recording is on the screen")
        let columns = (0 ..< 1920).filter { magenta(px($0, row)) }
        let left = try XCTUnwrap(columns.first), right = try XCTUnwrap(columns.last)
        XCTAssertGreaterThan(right - left, 700, "the recording fills the screen")
        let bar = px(left - 20, row)
        XCTAssertGreaterThan(bar.r + bar.g + bar.b, 2.4, "the white bar sits on the left, not mirrored")
        let mid = (left + right) / 2
        // Green above magenta: upright.
        let above = (0 ..< row).first { y in green(px(mid, y)) }
        XCTAssertNotNil(above, "green on top")
        // Black bezel above the picture, with the notch dipping into it at the middle.
        let top = try XCTUnwrap((0 ..< row).first { y in green(px(mid + 200, y)) })
        let bezel = px(mid + 200, top - 4)
        XCTAssertLessThan(bezel.r + bezel.g + bezel.b, 0.3, "a black bezel around the screen")
        let notch = px(mid, top + 4)
        XCTAssertLessThan(notch.r + notch.g + notch.b, 0.3, "the notch, black, over the top of the screen")
        // Below the screen, the keyboard base (yellow) shows.
        let base = (row ..< 1080).contains { y in let q = px(mid, y); return q.r > 0.6 && q.g > 0.55 && q.b < 0.55 }
        XCTAssertTrue(base, "the keyboard base below the screen")
    }

    func testMacsShowScreenRecordingsAndPhonesShowIPhoneTakes() {
        let mac = Self.screenProject()
        XCTAssertTrue(mac.device3D.applies(to: mac.clips[0]))
        XCTAssertTrue(mac.shows3D)
        var phone = mac
        phone.device3D.model = .iPhone17ProMax
        XCTAssertFalse(phone.device3D.applies(to: phone.clips[0]), "a phone doesn't show a screen recording")
        XCTAssertFalse(phone.shows3D)
        let device = Device3DTests.deviceProject()
        var onMac = device
        onMac.device3D.model = .macBookNeo
        XCTAssertFalse(onMac.device3D.applies(to: onMac.clips[0]), "nor a Mac an iPhone take")
        XCTAssertTrue(device.hasTakes(for: .phone))
        XCTAssertFalse(device.hasTakes(for: .laptop))
        let scene = RenderScene(project: phone, output: CGSize(width: 640, height: 360), cursor: CursorTrack(project: phone, logs: [:]))
        XCTAssertNil(scene.device3D(at: 1), "the screen recording stays flat")
    }

    func testEveryFinishKeepsTheKeyboardsPicture() throws {
        let out = CGSize(width: 960, height: 540)
        var p = Self.screenProject()
        p.device3D.placement = Device3DModel.macBookNeo.defaultPlacement
        for finish in Device3DModel.macBookNeo.finishes {
            p.device3D.finish = finish
            let px = pixels(render(p, output: out), size: out)
            // Across the keyboard: the keys' outlines make the colour change, rather than a flat fill.
            var levels: [Double] = []
            for x in stride(from: 300, to: 660, by: 2) { let q = px(x, 430); levels.append(q.r + q.g + q.b) }
            let spread = (levels.max() ?? 0) - (levels.min() ?? 0)
            XCTAssertGreaterThan(spread, 0.15, "\(finish.label): the keyboard's keys still show")
        }
    }

    // MARK: Lid

    func testLidHangsOnItsHingeAtTheBackOfTheBase() throws {
        let t = try template()
        let hinge = try XCTUnwrap(t.lidHinge, "the lid can turn")
        XCTAssertLessThan(hinge.z, t.bounds.min.z + 0.1, "the hinge is at the back")
        XCTAssertLessThan(hinge.y, t.bounds.min.y + 0.1, "down in the base")
        let lid = try XCTUnwrap(t.root.childNode(withName: Device3DTemplate.lidName, recursively: true))
        XCTAssertNotNil(lid.childNode(withName: Device3DTemplate.displayName, recursively: true), "the screen goes with the lid")
        XCTAssertGreaterThan(lid.childNodes.count, 1, "and the lid's shell, split from the base it's moulded with")
        XCTAssertLessThan(t.extent.min.z, t.bounds.min.z - 0.3, "leaning back, the lid reaches behind the base")
    }

    func testClosedLidHidesTheScreenAndOpensToShowIt() {
        let out = CGSize(width: 960, height: 540)
        var p = Self.screenProject()
        p.device3D.placement = Device3DPlacement(yaw: -16, pitch: -30, scale: 0.8, lid: 0)
        XCTAssertEqual(screenShown(pixels(render(p, output: out), size: out), size: out), 0, "shut, the screen faces the keys")
        p.device3D.lid = 45
        XCTAssertGreaterThan(screenShown(pixels(render(p, output: out), size: out), size: out), 200, "half open, it shows")
    }

    func testLidStaysWholeSeenFromBehind() {
        // The near plane once landed at twice its distance and sliced through the lid as the laptop turned.
        let out = CGSize(width: 960, height: 624)
        var p = Self.screenProject()
        p.style.padding = 0.06
        p.device3D.placement = Device3DPlacement(yaw: 160, pitch: -20, scale: 0.8)
        let px = pixels(render(p, output: out), size: out)
        func lid(_ y: Int) -> Int { (0 ..< 960).filter { x in let q = px(x, y); return q.r > 0.75 && q.g > 0.7 && q.b < 0.75 }.count }
        let high = lid(100), low = lid(360)
        XCTAssertGreaterThan(high, 400, "the back of the lid")
        XCTAssertGreaterThan(Double(low), Double(high) * 0.9, "as wide low down as up high")
    }

    func testProjectionsAreSetWithMetalsDepth() {
        let c = SCNCamera()
        c.fieldOfView = 30
        c.zNear = 1
        c.zFar = 10
        let m = Device3DStage.metalDepth * simd_float4x4(c.projectionTransform(withViewportSize: CGSize(width: 100, height: 100)))
        for (depth, z) in [(Float(1), Float(0)), (10, 1)] {
            let p = m * SIMD4(0, 0, -depth, 1)
            XCTAssertEqual(p.z / p.w, z, accuracy: 1e-4, "the near plane at 0, the far one at 1")
        }
    }

    func testCameraKeepsClearOfABigDeviceUnderAWideLens() throws {
        let t = try template()
        let gpu = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let stage = try XCTUnwrap(Device3DStage(model: .macBookNeo, template: t, device: gpu))
        var s = Self.screenProject().device3D
        s.perspective = 1
        let out = CGSize(width: 1280, height: 720), whole = CGRect(origin: .zero, size: out)
        var sizes: [Float] = []
        for scale in [0.8, 1.6, 3.0] {
            s.placement = Device3DPlacement(yaw: 180, pitch: -14, scale: scale)
            let request = Device3DRequest(output: out, view: whole, fit: whole.insetBy(dx: 60, dy: 60), pose: s.pose(at: 0),
                                          settings: s, landscape: false, display: nil)
            _ = stage.place(request)
            let distance = Double(stage.cameraNode.simdPosition.z)
            XCTAssertGreaterThan(distance - Double(t.radius) * scale, stage.camera.zNear, "scale \(scale): all of it in front of the camera")
            // Pixels to a unit at the device's middle: its size in the picture, before its own scale.
            sizes.append(Float(out.height) / (2 * tan(Float(stage.camera.fieldOfView) * .pi / 360) * Float(distance)))
        }
        XCTAssertEqual(sizes[1], sizes[0], accuracy: sizes[0] * 0.001, "backing away, it keeps its size")
        XCTAssertEqual(sizes[2], sizes[0], accuracy: sizes[0] * 0.001)
    }

    func testLidKeyframesMoveItAndOldPosesStandOpen() throws {
        var s = Device3DSettings()
        s.model = .macBookNeo
        s.keyframes = [Device3DKeyframe(time: 0, placement: Device3DPlacement(lid: 0)), Device3DKeyframe(time: 1, placement: Device3DPlacement(lid: 90))]
        let lids = stride(from: 0.0, through: 1.0, by: 0.25).map { s.placement(at: $0).lid }
        XCTAssertEqual(lids.first, 0)
        XCTAssertEqual(lids.last, 90)
        XCTAssertEqual(lids, lids.sorted(), "it opens steadily")
        XCTAssertEqual(s.pose(at: 1).lid, .pi / 2, accuracy: 1e-9)
        let saved = #"{"yaw":1,"pitch":2,"rotation":0,"position":[0,0],"scale":1}"#
        XCTAssertEqual(try JSONDecoder().decode(Device3DPlacement.self, from: Data(saved.utf8)).lid, Device3DPlacement.openLid)
        var settings = Device3DSettings()
        settings.lid = 30
        let round = try JSONDecoder().decode(Device3DSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertEqual(round.lid, 30)
    }

    // MARK: Every Mac

    func testMacBookAirStandsOnItsBaseWithItsLidLeaningBack() throws {
        let m = Device3DModel.macBookAir15
        XCTAssertEqual(m.kind, .laptop)
        XCTAssertEqual(Device3DRenderer.shared.status(for: m), .ready(hasDisplayMesh: true))
        let t = try template(m)
        // Its file has the lid 20° past upright over a level base; read even a degree or two off, the lid closed onto
        // the keys at an angle, gaping at the hinge.
        XCTAssertEqual(Double(t.lidOpening) * 180 / .pi, 110.2, accuracy: 0.6, "its lid as modelled, leaning back")
        XCTAssertNotNil(t.lidHinge)
        XCTAssertGreaterThan(t.size.z, 0.9, "its base laid flat, reaching out in front")
        XCTAssertEqual(try XCTUnwrap(Device3DRenderer.shared.displayAspect(for: m)), 1.55, accuracy: 0.06)
        XCTAssertEqual(Double(try template().lidOpening), .pi / 2, accuracy: 1e-6, "the Neo's lid is modelled upright")
    }

    func testEveryMacShowsTheRecordingAndClosesOverIt() {
        let out = CGSize(width: 960, height: 540)
        for model in Device3DModel.models(.laptop) {
            var p = Self.screenProject()
            p.device3D.model = model
            p.device3D.finish = model.finishes[0]
            p.device3D.placement = Device3DPlacement(yaw: -16, pitch: -20, scale: 0.8)
            XCTAssertGreaterThan(screenShown(pixels(render(p, output: out), size: out), size: out), 2000, "\(model.label): open, it shows")
            p.device3D.lid = 0
            XCTAssertEqual(screenShown(pixels(render(p, output: out), size: out), size: out), 0, "\(model.label): shut, it doesn't")
        }
    }
}
