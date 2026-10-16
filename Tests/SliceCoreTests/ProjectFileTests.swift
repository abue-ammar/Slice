//
//  ProjectFileTests.swift
//  SliceCoreTests
//
//  Created by rit3zh CX on 10/15/26.
//

@testable import SliceCore
import XCTest

final class ProjectFileTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("slice-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func editedProject() throws -> (ProjectBundle, Project) {
        let (bundle, empty) = try ProjectBundle.create(name: "Demo", in: dir)
        var p = empty
        let id = UUID()
        let (clipDir, rel) = try bundle.makeClipFolder(id: id)
        try Data("movie".utf8).write(to: clipDir.appendingPathComponent("screen.mov"))
        let log = CursorLog(samples: [CursorLog.Sample(t: 0, x: 0.2, y: 0.3), CursorLog.Sample(t: 1, x: 0.6, y: 0.4)])
        try JSONEncoder().encode(log).write(to: clipDir.appendingPathComponent("cursor.json"))
        p.clips = [Clip(id: id, screenFile: "\(rel)/screen.mov", cursorFile: "\(rel)/cursor.json", duration: 10,
                        screenPixelSize: CGSize(width: 100, height: 100), captureRect: CGRect(x: 0, y: 0, width: 100, height: 100))]
        p.zoomBlocks = [ZoomBlock(start: 1, end: 4, scale: 2, focus: CGPoint(x: 0.8, y: 0.15))]
        p.cuts = [Cut(clipID: id, start: 6, end: 7)]
        p.micVolume = 0.4
        try bundle.save(p)
        return (bundle, p)
    }

    func testSentProjectOpensWithEverything() throws {
        let (bundle, saved) = try editedProject()
        let elsewhere = dir.appendingPathComponent("Received", isDirectory: true)
        let copy = try bundle.copy(into: elsewhere)
        let renamed = elsewhere.appendingPathComponent("Walkthrough.slice")
        try FileManager.default.moveItem(at: copy.url, to: renamed)

        let opened = try ProjectBundle(opening: renamed)
        let loaded = try opened.load()
        XCTAssertEqual(loaded.name, "Walkthrough")
        var expected = saved
        expected.name = "Walkthrough"
        XCTAssertEqual(loaded, expected)
        XCTAssertEqual(opened.loadCursorLogs(for: loaded)[saved.clips[0].id]?.samples.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: opened.file(loaded.clips[0].screenFile).path))
        XCTAssertTrue(opened.isWritable)
    }

    func testCopyPicksFreeName() throws {
        let (bundle, _) = try editedProject()
        let copy = try bundle.copy(into: dir)
        XCTAssertEqual(copy.url.lastPathComponent, "Demo 2.slice")
    }

    func testCopyOfReadOnlyProjectCanBeSaved() throws {
        let (bundle, saved) = try editedProject()
        let lock: (Int) throws -> Void = { mode in
            for path in [bundle.url.path, bundle.projectURL.path] {
                try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
            }
        }
        try lock(0o555)
        defer { try? lock(0o755) }
        XCTAssertFalse(bundle.isWritable)
        let copy = try bundle.copy(into: dir.appendingPathComponent("Library"))
        XCTAssertTrue(copy.isWritable)
        var edited = try copy.load()
        edited.micVolume = 0.9
        try copy.save(edited)
        XCTAssertEqual(try copy.load().micVolume, 0.9)
        XCTAssertEqual(try bundle.load().micVolume, saved.micVolume)
    }

    func testOnlyProjectsOpen() throws {
        let folder = dir.appendingPathComponent("Not a project.slice")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ProjectBundle(opening: folder))
        XCTAssertThrowsError(try ProjectBundle(opening: dir))
    }

    func testLegacyProjectsAreRenamed() throws {
        let (bundle, saved) = try editedProject()
        let legacy = dir.appendingPathComponent("Old.screenrec")
        try FileManager.default.moveItem(at: bundle.url, to: legacy)

        let listed = ProjectBundle.list(in: dir)
        XCTAssertEqual(listed.map(\.url.lastPathComponent), ["Old.slice"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertEqual(try listed[0].load().zoomBlocks, saved.zoomBlocks)
    }

    func testListAddsProjectsFromElsewhereOnce() throws {
        let (bundle, _) = try editedProject()
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("slice-other-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: other) }
        let outside = try bundle.copy(into: other)
        let gone = other.appendingPathComponent("Deleted.slice")

        let listed = ProjectBundle.list(in: dir, adding: [outside.url, bundle.url, gone])
        XCTAssertEqual(Set(listed.map(\.url.lastPathComponent)), ["Demo.slice"])
        XCTAssertEqual(listed.count, 2)
    }
}
