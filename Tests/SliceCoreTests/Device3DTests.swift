//
//  Device3DTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/15/26.
//

import AVFoundation
import AppKit
import CoreImage
@testable import SliceCore
import SceneKit
import XCTest

/// The 3D iPhone. Set RENDER_OUT to a directory to also write PNGs for eyeballing.
final class Device3DTests: XCTestCase {
    static let portraitCanvas = CGSize(width: 660, height: 1434)
    static let green = CIColor(red: 0.1, green: 0.8, blue: 0.3)
    static let magenta = CIColor(red: 0.85, green: 0.1, blue: 0.7)

    /// A device take's picture: green over magenta (the phone's top is green), or green left of magenta on its side.
    static func display(_ size: CGSize, landscape: Bool = false) -> CIImage {
        let whole = CGRect(origin: .zero, size: size)
        let top = landscape ? CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)
            : CGRect(x: 0, y: size.height / 2, width: size.width, height: size.height / 2)
        return CIImage(color: green).cropped(to: top).composited(over: CIImage(color: magenta).cropped(to: whole))
    }

    static func deviceProject(canvas: CGSize = portraitCanvas, frame: String? = nil, screen: CGRect? = nil) -> Project {
        var p = Project(name: "3D")
        var clip = Clip(screenFile: "s.mov", duration: 10, screenPixelSize: canvas,
                        captureRect: CGRect(x: 0, y: 0, width: canvas.width / 3, height: canvas.height / 3), cursorInVideo: false)
        clip.device = RecordedDevice(name: "iPhone", identifier: "iPhone18,2", frame: frame, color: frame == nil ? nil : "Cosmic Orange",
                                     screen: screen, opensIn3D: true)
        p.clips = [clip]
        p.device3D.enabled = true
        p.device3D.yaw = 0
        p.device3D.pitch = 0
        return p
    }

    let renderer = FrameRenderer()

    func pixels(_ image: CIImage, size: CGSize) -> (Int, Int) -> (r: Double, g: Double, b: Double, a: Double) {
        let cg = renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: size),
                                                format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))!
        let data = cg.dataProvider!.data! as Data
        let row = cg.bytesPerRow
        return { x, y in
            let o = y * row + x * 4
            return (Double(data[o]) / 255, Double(data[o + 1]) / 255, Double(data[o + 2]) / 255, Double(data[o + 3]) / 255)
        }
    }

    func close(_ p: (r: Double, g: Double, b: Double, a: Double), _ c: CIColor, within: Double = 0.12,
               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(p.r, Double(c.red), accuracy: within, "red", file: file, line: line)
        XCTAssertEqual(p.g, Double(c.green), accuracy: within, "green", file: file, line: line)
        XCTAssertEqual(p.b, Double(c.blue), accuracy: within, "blue", file: file, line: line)
    }

    func isOrange(_ p: (r: Double, g: Double, b: Double, a: Double)) -> Bool { p.r > 0.45 && p.r > p.g * 1.6 && p.b < p.g * 0.8 }

    func write(_ image: CIImage, size: CGSize, _ name: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["RENDER_OUT"] else { return }
        let cg = renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: size))!
        try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func render(_ project: Project, output: CGSize, at t: Double = 1, screen: CIImage? = nil) -> CIImage {
        let scene = RenderScene(project: project, output: output, cursor: CursorTrack(project: project, logs: [:]))
        return renderer.render(scene: scene, time: t, screen: screen ?? Self.display(project.clips[0].screenPixelSize), camera: nil)
    }

    // MARK: - Settings

    func testOlderProjectsOpenWithThe3DPhoneOff() throws {
        var p = Project(name: "Old")
        p.clips = [Clip(screenFile: "s.mov", duration: 2, screenPixelSize: CGSize(width: 100, height: 100), captureRect: .zero)]
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        json["device3D"] = nil
        let decoded = try JSONDecoder().decode(Project.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(decoded.device3D, Device3DSettings())
        XCTAssertFalse(decoded.device3D.enabled)
        XCTAssertFalse(decoded.hasDeviceRecording)

        let partial = try JSONDecoder().decode(Device3DSettings.self, from: Data(#"{"enabled":true,"finish":"deepBlue","animation":{"motion":"sway"}}"#.utf8))
        XCTAssertTrue(partial.enabled)
        XCTAssertEqual(partial.finish, .deepBlue)
        XCTAssertEqual(partial.animation.motion, .sway)
        XCTAssertEqual(partial.animation.duration, Device3DAnimation().duration)
        XCTAssertEqual(partial.scale, 1)
    }

    func testSettingsRoundTripWithTheProject() throws {
        var p = Self.deviceProject()
        p.device3D.finish = .silver
        p.device3D.position = CGPoint(x: 0.1, y: -0.05)
        p.device3D.animation.motion = .float
        p.device3D.background = .studio
        let back = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back, p)
        XCTAssertEqual(back.clips[0].device?.opensIn3D, true)
        XCTAssertTrue(back.hasDeviceRecording)
    }

    // MARK: - Pose

    func testSwayStartsOnTheChosenSideRestsAndEasesAcross() {
        var s = Device3DSettings()
        s.yaw = 10
        s.animation.motion = .sway
        s.animation.swing = 30
        s.animation.duration = 4
        s.animation.hold = 0.2
        let r = Double.pi / 180
        XCTAssertEqual(s.pose(at: 0).yaw, 40 * r, accuracy: 1e-9)
        XCTAssertEqual(s.pose(at: 0.3).yaw, 40 * r, accuracy: 1e-9, "rests at the end")
        XCTAssertEqual(s.pose(at: 2).yaw, 10 * r, accuracy: 1e-6, "crosses its own pose halfway")
        XCTAssertEqual(s.pose(at: 4).yaw, -20 * r, accuracy: 1e-9)
        XCTAssertEqual(s.pose(at: 8).yaw, 40 * r, accuracy: 1e-9, "and swings back")
        s.animation.startSide = .left
        XCTAssertEqual(s.pose(at: 0).yaw, -20 * r, accuracy: 1e-9)
        // Continuous: no jumps between neighbouring frames anywhere, including across swings.
        var last = s.pose(at: 0).yaw
        for i in 1 ... 1200 {
            let now = s.pose(at: Double(i) / 60).yaw
            XCTAssertLessThan(abs(now - last), 0.03)
            last = now
        }
        XCTAssertEqual(s.pose(at: 3.7), s.pose(at: 3.7), "the same moment always gets the same pose")
    }

    func testPoseIsFreeAndAddsAZoomsTilt() throws {
        var s = Device3DSettings()
        s.yaw = -170
        s.pitch = 95
        s.rotation = 45
        s.position = CGPoint(x: -0.9, y: 0.8)
        s.scale = 3.5
        let pose = s.pose(at: 5)
        XCTAssertEqual(pose.yaw, -170 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(pose.pitch, 95 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(pose.roll, 45 * .pi / 180, accuracy: 1e-9)
        XCTAssertEqual(pose.offset, CGPoint(x: -0.9, y: 0.8))
        XCTAssertEqual(pose.scale, 3.5)
        var tilt = ZoomTilt()
        tilt.enabled = true
        XCTAssertEqual(s.pose(at: 5, extra: tilt.pose).yaw, pose.yaw + tilt.pose.yaw, accuracy: 1e-9)
        s.animation.motion = .float
        XCTAssertNotEqual(s.pose(at: 1).offset, s.pose(at: 2).offset)

        // Saved with the earlier direction and strength: the same pose in free angles.
        let old = try JSONDecoder().decode(Device3DSettings.self, from: Data(#"{"tiltDirection":"left","tiltStrength":0.5,"lean":4}"#.utf8))
        XCTAssertEqual(old.yaw, -17.5, accuracy: 1e-9)
        XCTAssertEqual(old.pitch, 3.5 + 4, accuracy: 1e-9)
        let back = try JSONDecoder().decode(Device3DSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back, s)
    }

    // MARK: - Display geometry

    func testDisplayRectComesFromTheRecordedOpening() throws {
        var p = Self.deviceProject(canvas: CGSize(width: 1520, height: 3068), frame: "17 Pro Max",
                                   screen: CGRect(x: 100.0 / 1520, y: 100.0 / 3068, width: 1320.0 / 1520, height: 2868.0 / 3068))
        XCTAssertEqual(p.clips[0].deviceDisplayRect, CGRect(x: 100, y: 100, width: 1320, height: 2868))
        XCTAssertFalse(p.clips[0].isLandscapeDevice)
        p.clips[0].device?.screen = nil
        p.clips[0].device?.frame = nil
        XCTAssertEqual(p.clips[0].deviceDisplayRect, CGRect(x: 0, y: 0, width: 1520, height: 3068), "frameless is all display")
        p.clips[0].device = nil
        XCTAssertNil(p.clips[0].deviceDisplayRect)
    }

    func testOpeningMeasuredFromAFrameMatchesItsDisplay() throws {
        let catalog = DeviceTests.catalog
        let def = try XCTUnwrap(try catalog.definition(model: "17 Pro Max", color: .cosmicOrange))
        for landscape in [false, true] {
            let layout = DeviceLayout(frame: def, streamSize: landscape ? CGSize(width: 2868, height: 1320) : CGSize(width: 1320, height: 2868))
            var p = Self.deviceProject(canvas: layout.canvas, frame: "17 Pro Max", screen: layout.screenRect)
            p.clips[0].device?.screen = layout.screenRect
            let r = try XCTUnwrap(p.clips[0].deviceDisplayRect)
            XCTAssertEqual(p.clips[0].isLandscapeDevice, landscape)
            XCTAssertEqual(r.width, landscape ? 2868 : 1320, accuracy: 4)
            XCTAssertEqual(r.height, landscape ? 1320 : 2868, accuracy: 4)
        }
    }

    // MARK: - Model

    func testBundledModelLoadsWithItsDisplay() throws {
        XCTAssertEqual(Device3DRenderer.shared.status(for: .iPhone17ProMax), .ready(hasDisplayMesh: true))
        let aspect = try XCTUnwrap(Device3DRenderer.shared.displayAspect(for: .iPhone17ProMax))
        XCTAssertEqual(aspect, 1320.0 / 2868, accuracy: 0.015, "the display has the real screen's shape")
    }

    func testEveryModelLoadsAndShowsTheRecordingUprightFrontAndNotThroughItsBack() throws {
        let out = CGSize(width: 540, height: 960)
        let screenAspect: [Device3DModel: Double] = [.iPhone17ProMax: 1320.0 / 2868, .iPhoneAir: 1260.0 / 2736, .iPhone16ProMax: 1320.0 / 2868,
                                                     .iPhone16Plus: 1290.0 / 2796, .iPhone15ProMax: 1290.0 / 2796, .iPhone14ProMax: 1290.0 / 2796]
        for model in Device3DModel.models(.phone) {
            XCTAssertEqual(Device3DRenderer.shared.status(for: model), .ready(hasDisplayMesh: true), model.label)
            let aspect = try XCTUnwrap(Device3DRenderer.shared.displayAspect(for: model))
            XCTAssertEqual(aspect, screenAspect[model]!, accuracy: 0.03, "\(model.label) display has the screen's shape")
            var p = Self.deviceProject()
            p.device3D.model = model
            p.device3D.background = .color
            for finish in model.finishes {
                p.device3D.finish = finish
                p.device3D.yaw = 0
                let front = pixels(render(p, output: out), size: out)
                close(front(270, 480 - 200), Self.green, within: 0.15)
                close(front(270, 480 + 200), Self.magenta, within: 0.15)
                p.device3D.yaw = 180
                let back = render(p, output: out)
                try write(back, size: out, "3d_back_\(model.shortLabel)_\(finish.rawValue)")
                let b = pixels(back, size: out)
                for y in [380, 680] {
                    let q = b(270, y)
                    let shows = [Self.magenta, Self.green].contains { c in
                        abs(q.r - Double(c.red)) < 0.07 && abs(q.g - Double(c.green)) < 0.07 && abs(q.b - Double(c.blue)) < 0.07
                    }
                    XCTAssertFalse(shows, "\(model.label) \(finish.label): the back hides the screen")
                }
            }
        }
    }

    func testIPhone14ProMaxLoadsDrawsUprightAndTakesEveryFinish() throws {
        XCTAssertEqual(Device3DRenderer.shared.status(for: .iPhone14ProMax), .ready(hasDisplayMesh: true))
        let aspect = try XCTUnwrap(Device3DRenderer.shared.displayAspect(for: .iPhone14ProMax))
        XCTAssertEqual(aspect, 1290.0 / 2796, accuracy: 0.015)
        let out = CGSize(width: 1080, height: 1920)
        var p = Self.deviceProject()
        p.device3D.model = .iPhone14ProMax
        p.device3D.background = .color
        for finish in Device3DModel.iPhone14ProMax.finishes {
            p.device3D.finish = finish
            p.device3D.yaw = 24
            let image = render(p, output: out)
            try write(image, size: out, "3d_14_\(finish.rawValue)")
            let px = pixels(image, size: out)
            close(px(540, 960 - 400), Self.green)
            close(px(540, 960 + 400), Self.magenta)
            // Nothing modelled around the phone is drawn: the frame's corners are the background.
            XCTAssertLessThan(px(20, 20).r + px(20, 20).g, 0.5)
            XCTAssertLessThan(px(1060, 1900).r + px(1060, 1900).g, 0.5)
        }
        // A finish another model comes in falls back to this one's own when the project opens.
        let json = #"{"model":"iPhone 14 Pro Max","finish":"cosmicOrange"}"#
        XCTAssertEqual(try JSONDecoder().decode(Device3DSettings.self, from: Data(json.utf8)).finish, .deepPurple)
    }

    func testKeyframesAnimateThePhoneBetweenPoses() throws {
        var s = Device3DSettings()
        XCTAssertEqual(s.placement(at: 3), s.placement, "no keyframes: the pose controls")
        let a = Device3DPlacement(yaw: 170, pitch: 0, rotation: 0, position: .zero, scale: 1)
        let b = Device3DPlacement(yaw: -170, pitch: 40, rotation: 90, position: CGPoint(x: 0.4, y: 0), scale: 2)
        s.keyframes = [Device3DKeyframe(time: 4, placement: b, easing: .linear), Device3DKeyframe(time: 2, placement: a)]
        XCTAssertEqual(s.placement(at: 0), a, "held before the first")
        XCTAssertEqual(s.placement(at: 9), b, "held after the last")
        let mid = s.placement(at: 3)
        XCTAssertEqual(abs(mid.yaw), 180, accuracy: 1e-6, "turns the short way round, through the back")
        XCTAssertEqual(mid.pitch, 20, accuracy: 1e-6)
        XCTAssertEqual(mid.rotation, 45, accuracy: 1e-6)
        XCTAssertEqual(mid.position.x, 0.2, accuracy: 1e-6)
        XCTAssertEqual(mid.scale, sqrt(2), accuracy: 1e-6, "size changes evenly, in ratio")
        XCTAssertEqual(s.pose(at: 3).pitch, 20 * .pi / 180, accuracy: 1e-6)

        // Posing at a keyframe changes it; posing between keyframes adds one there; with none, the controls change.
        var edit = s
        let at2 = edit.setPlacement(Device3DPlacement(yaw: 5), at: 2.01)
        XCTAssertEqual(edit.keyframes.count, 2)
        XCTAssertEqual(edit.keyframes.first { $0.id == at2 }?.placement.yaw, 5)
        let added = try XCTUnwrap(edit.setPlacement(Device3DPlacement(yaw: 9), at: 3))
        XCTAssertEqual(edit.keyframes.map(\.time), [2, 3, 4])
        XCTAssertEqual(edit.keyframes.first { $0.id == added }?.placement.yaw, 9)
        var plain = Device3DSettings()
        XCTAssertNil(plain.setPlacement(Device3DPlacement(yaw: -30), at: 1))
        XCTAssertEqual(plain.yaw, -30)
        let back = try JSONDecoder().decode(Device3DSettings.self, from: JSONEncoder().encode(edit))
        XCTAssertEqual(back, edit)
    }

    func testCustomCurvesShapeKeyframesAndTheSway() throws {
        var s = Device3DSettings()
        let a = Device3DPlacement(yaw: 0, pitch: 0), b = Device3DPlacement(yaw: 40, pitch: 0)
        let overshoot = CubicBezier(0.34, 1.56, 0.64, 1)
        s.keyframes = [Device3DKeyframe(time: 0, placement: a), Device3DKeyframe(time: 1, placement: b, easing: .custom, curve: overshoot)]
        for f in [0.25, 0.5, 0.75] {
            XCTAssertEqual(s.placement(at: f).yaw, 40 * overshoot(f), accuracy: 1e-9)
        }
        XCTAssertGreaterThan((0 ... 100).map { s.placement(at: Double($0) / 100).yaw }.max()!, 40, "an overshooting curve swings past the pose")
        XCTAssertEqual(s.placement(at: 1).yaw, 40, accuracy: 1e-9, "and lands on it")
        let back = try JSONDecoder().decode(Device3DSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.keyframes[1].curve, overshoot)
        XCTAssertEqual(back.keyframes[1].easing, .custom)

        var sway = Device3DSettings()
        sway.yaw = 0
        sway.animation.motion = .sway
        sway.animation.hold = 0
        sway.animation.duration = 2
        sway.animation.swing = 30
        sway.animation.easing = .custom
        sway.animation.curve = CubicBezier(0, 0, 1, 1)
        XCTAssertEqual(sway.pose(at: 0.5).yaw, 15 * .pi / 180, accuracy: 1e-6, "a straight curve swings evenly")
    }

    func testThumbnailsShowEachPhoneOnAClearBackground() throws {
        for model in Device3DModel.allCases {
            let cg = try XCTUnwrap(Device3DRenderer.shared.thumbnail(model: model, finish: model.finishes.last!,
                                                                    placement: Device3DPlacement(yaw: 24, pitch: 6),
                                                                    size: CGSize(width: 192, height: 208)))
            XCTAssertEqual(cg.width, 192)
            let px = pixels(CIImage(cgImage: cg), size: CGSize(width: 192, height: 208))
            XCTAssertLessThan(px(2, 2).a, 0.05, "\(model) clear around the phone")
            XCTAssertGreaterThan(px(96, 104).a, 0.95, "\(model) the phone in the middle")
        }
    }

    func testAModelWithoutADisplayGetsOneOnItsFront() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("3d-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let scene = SCNScene()
        let body = SCNNode(geometry: SCNBox(width: 7.5, height: 16, length: 0.8, chamferRadius: 0.5))
        body.geometry?.firstMaterial?.name = "body"
        scene.rootNode.addChildNode(body)
        let url = dir.appendingPathComponent("blank.scn")
        XCTAssertTrue(scene.write(to: url, options: nil, delegate: nil, progressHandler: nil))
        let template = try Device3DTemplate(url: url, name: "Blank")
        XCTAssertFalse(template.hasDisplayMesh)
        XCTAssertEqual(template.size.y, 1, accuracy: 1e-3)
        XCTAssertGreaterThan(template.displaySize.width, 0.3)
        XCTAssertNotNil(template.root.childNode(withName: Device3DTemplate.displayName, recursively: true))

        let junk = dir.appendingPathComponent("junk.usdz")
        try Data("not a model".utf8).write(to: junk)
        XCTAssertThrowsError(try Device3DTemplate(url: junk, name: "Junk")) { error in
            XCTAssertEqual(error as? Device3DError, .unreadable("Junk"))
        }
    }
}
