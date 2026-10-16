//
//  KeystrokeTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/13/26.
//

import CoreImage
import ImageIO
@testable import SliceCore
import UniformTypeIdentifiers
import XCTest

final class KeystrokeTests: XCTestCase {
    let out = CGSize(width: 1920, height: 1080)

    func press(_ t: Double, _ modifiers: String = "⌘", _ key: String = "K") -> KeyPress {
        KeyPress(t: t, modifiers: modifiers, key: key)
    }

    func project(cuts: [Cut] = []) -> Project {
        var p = Project(name: "Keys")
        p.clips = [Clip(screenFile: "s.mov", cursorFile: "c.json", duration: 10, screenPixelSize: CGSize(width: 3024, height: 1964),
                        captureRect: CGRect(x: 0, y: 0, width: 1512, height: 982))]
        p.cuts = cuts
        p.cursor.visible = false
        p.cursor.clickEffect = .none
        return p
    }

    func scene(_ keys: [KeyPress], _ edit: (inout Project) -> Void = { _ in }) -> RenderScene {
        var p = project()
        edit(&p)
        let log = CursorLog(samples: [.init(t: 0, x: 0.5, y: 0.5)], keys: keys)
        return RenderScene(project: p, output: out, cursor: CursorTrack(project: p, logs: [p.clips[0].id: log]))
    }

    // MARK: - Naming

    func testNamesShortcutsAndKeys() {
        let k = KeyPress.make(t: 0, keyCode: 40, characters: "k", control: false, option: false, shift: true, command: true)
        XCTAssertEqual(k?.label, "⇧⌘ K")
        XCTAssertEqual(KeyPress.make(t: 0, keyCode: 53, characters: nil, control: false, option: false, shift: false, command: false)?.label,
                       "esc")
        XCTAssertEqual(KeyPress.make(t: 0, keyCode: 125, characters: nil, control: true, option: true, shift: false, command: false)?.label,
                       "⌃⌥ ↓")
        XCTAssertEqual(KeyPress.make(t: 0, keyCode: 49, characters: " ", control: true, option: false, shift: false, command: false)?.label,
                       "⌃ Space")
    }

    func testNeverRecordsTyping() {
        XCTAssertNil(KeyPress.make(t: 0, keyCode: 0, characters: "a", control: false, option: false, shift: false, command: false))
        XCTAssertNil(KeyPress.make(t: 0, keyCode: 0, characters: "a", control: false, option: false, shift: true, command: false))
        XCTAssertNil(KeyPress.make(t: 0, keyCode: 49, characters: " ", control: false, option: false, shift: false, command: false))
    }

    // MARK: - Timeline

    func testShortcutsOnlyUnlessSingleKeys() {
        let keys = [press(1), press(3, "", "esc")]
        XCTAssertEqual(scene(keys).keystrokes.states(at: 3.5).count, 0)
        XCTAssertEqual(scene(keys) { $0.keystrokes.singleKeys = true }.keystrokes.states(at: 3.5).first?.label, "esc")
        XCTAssertTrue(scene(keys) { $0.keystrokes.visible = false }.keystrokes.isEmpty)
    }

    func testComesIntoFocusHoldsAndLeaves() throws {
        let s = scene([press(1)])
        XCTAssertTrue(s.keystrokes.states(at: 0.99).isEmpty)
        let start = try XCTUnwrap(s.keystrokes.states(at: 1.01).first)
        XCTAssertGreaterThan(start.blur, 0.8)
        XCTAssertLessThan(start.opacity, 0.2)
        XCTAssertLessThan(start.scale, 1)
        let held = try XCTUnwrap(s.keystrokes.states(at: 2).first)
        XCTAssertEqual(held.blur, 0)
        XCTAssertEqual(held.opacity, 1)
        XCTAssertEqual(held.scale, 1)
        XCTAssertEqual(held.drop, 0)
        let leaving = try XCTUnwrap(s.keystrokes.states(at: 1 + 1.4 + 0.1).first)
        XCTAssertGreaterThan(leaving.blur, 0.3)
        XCTAssertTrue(s.keystrokes.states(at: 1 + 1.4 + 0.3).isEmpty)
    }

    func testNextShortcutReplacesTheCurrentOne() throws {
        let s = scene([press(1), press(1.8, "⇧⌘", "P")])
        let swap = s.keystrokes.states(at: 1.86)
        XCTAssertEqual(swap.map(\.label), ["⌘ K", "⇧⌘ P"])
        XCTAssertGreaterThan(swap[0].blur, swap[1].blur - 1)
        XCTAssertEqual(s.keystrokes.states(at: 2).map(\.label), ["⇧⌘ P"])
        XCTAssertEqual(try XCTUnwrap(s.keystrokes.states(at: 2.5).first).blur, 0)
    }

    func testRepeatsCountUpInPlace() throws {
        let s = scene([press(1, "⌘", "Z"), press(1.5, "⌘", "Z"), press(1.9, "⌘", "Z")])
        XCTAssertEqual(s.keystrokes.states(at: 1.45).first?.count, 1)
        let pulse = try XCTUnwrap(s.keystrokes.states(at: 1.55).first)
        XCTAssertGreaterThan(pulse.blur, 0.2)
        XCTAssertEqual(pulse.opacity, 1)
        XCTAssertEqual(s.keystrokes.states(at: 1.7).first?.count, 2)
        XCTAssertEqual(s.keystrokes.states(at: 2.5).first?.count, 3)
        XCTAssertEqual(s.keystrokes.states(at: 3.2).first?.opacity, 1)
    }

    func testFollowsCuts() {
        var p = project()
        p.cuts = [Cut(clipID: p.clips[0].id, start: 2, end: 4)]
        let log = CursorLog(keys: [press(3), press(5, "⌘", "S")])
        let track = CursorTrack(project: p, logs: [p.clips[0].id: log])
        XCTAssertEqual(track.keys.map(\.label), ["⌘ S"])
        XCTAssertEqual(track.keys.first?.t ?? 0, 3, accuracy: 1e-9)
    }

    func testOldLogsDecodeWithoutKeys() throws {
        let json = #"{"samples":[],"clicks":[]}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(CursorLog.self, from: json).keys, [])
        let project = try JSONDecoder().decode(Project.self, from: #"{"name":"Old"}"#.data(using: .utf8)!)
        XCTAssertEqual(project.keystrokes, KeystrokeSettings())
    }

    // MARK: - Rendering

    func render(_ s: RenderScene, at t: Double) throws -> CGImage {
        let renderer = FrameRenderer()
        let screen = CIImage(color: CIColor(red: 0.62, green: 0.45, blue: 0.9)).cropped(to: CGRect(x: 0, y: 0, width: 3024, height: 1964))
        let image = renderer.render(scene: s, time: t, screen: screen, camera: nil)
        return try XCTUnwrap(renderer.context.createCGImage(image, from: CGRect(origin: .zero, size: out)))
    }

    func testDrawsOnlyWhileShowing() throws {
        let s = scene([press(1)])
        let before = try render(s, at: 0.5), during = try render(s, at: 1.8), after = try render(s, at: 4)
        XCTAssertEqual(before.dataProvider?.data, after.dataProvider?.data)
        XCTAssertNotEqual(before.dataProvider?.data, during.dataProvider?.data)
    }

    /// Writes a contact sheet of the animation for eyeballing: KEYSTROKE_FRAMES=/some/dir swift test --filter testDump
    func testDumpFrames() throws {
        guard let dir = ProcessInfo.processInfo.environment["KEYSTROKE_FRAMES"] else { throw XCTSkip("set KEYSTROKE_FRAMES") }
        let s = scene([press(0.2), press(1.2, "", "↓"), press(1.6, "", "↓"), press(2.0, "⇧⌘", "P")]) { $0.keystrokes.singleKeys = true }
        var t = 0.15
        while t < 3.9 {
            let cg = try render(s, at: t)
            let crop = try XCTUnwrap(cg.cropping(to: CGRect(x: 760, y: 840, width: 400, height: 240)))
            let url = URL(fileURLWithPath: dir).appendingPathComponent(String(format: "k_%06.3f.png", t))
            let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(dest, crop, nil)
            CGImageDestinationFinalize(dest)
            t += 1.0 / 30
        }
    }
}
