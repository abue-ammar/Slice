//
//  ProjectBundle.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/4/26.
//

import CoreImage
import Foundation

/// On-disk project: a `<name>.slice` package holding `project.json` and `clips/<id>/{screen.mov,camera.mov,mic.m4a,cursor.json}`.
/// Everything the project uses (imported audio, backgrounds, transcripts, enhanced voices) lives inside it under
/// relative paths, so the package can be moved, renamed or sent to someone else and opens with every edit intact.
public struct ProjectBundle {
    public static let fileExtension = "slice"
    public static let legacyExtension = "screenrec"
    public let url: URL

    public init(url: URL) { self.url = url }

    public static var defaultDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["SCREENREC_PROJECTS_DIR"] { return URL(fileURLWithPath: dir) }
        return migrated(FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0], "Screen Recorder", to: "Slice")
    }

    static func migrated(_ base: URL, _ old: String, to new: String) -> URL {
        let url = base.appendingPathComponent(new), legacy = base.appendingPathComponent(old)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path), fm.fileExists(atPath: legacy.path) { try? fm.moveItem(at: legacy, to: url) }
        return url
    }

    public static func create(name: String, in dir: URL = defaultDirectory) throws -> (ProjectBundle, Project) {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var candidate = dir.appendingPathComponent("\(name).\(fileExtension)")
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(name) \(n).\(fileExtension)")
            n += 1
        }
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        let bundle = ProjectBundle(url: candidate)
        let project = Project(name: candidate.deletingPathExtension().lastPathComponent)
        try bundle.save(project)
        return (bundle, project)
    }

    public static func list(in dir: URL = defaultDirectory, adding others: [URL] = []) -> [ProjectBundle] {
        migrateLegacy(in: dir)
        let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var seen = Set<String>()
        return (items.filter { $0.pathExtension == fileExtension } + others.filter(isProject))
            .filter { seen.insert($0.resolvingSymlinksInPath().path).inserted }
            .sorted { modified($0) > modified($1) }
            .map { ProjectBundle(url: $0) }
    }

    public static func isProject(_ url: URL) -> Bool {
        guard [fileExtension, legacyExtension].contains(url.pathExtension.lowercased()) else { return false }
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("project.json").path)
    }

    static func migrateLegacy(in dir: URL) {
        let fm = FileManager.default
        for item in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        where item.pathExtension == legacyExtension {
            let dest = item.deletingPathExtension().appendingPathExtension(fileExtension)
            if !fm.fileExists(atPath: dest.path) { try? fm.moveItem(at: item, to: dest) }
        }
    }

    public init(opening url: URL) throws {
        guard Self.isProject(url) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path,
                NSLocalizedDescriptionKey: "“\(url.lastPathComponent)” isn't a Slice project."])
        }
        self.init(url: url)
    }

    public var isWritable: Bool {
        let fm = FileManager.default
        return fm.isWritableFile(atPath: url.path) && fm.isWritableFile(atPath: projectURL.path)
    }

    public func copy(into dir: URL = defaultDirectory) throws -> ProjectBundle {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = url.deletingPathExtension().lastPathComponent
        var dest = dir.appendingPathComponent("\(name).\(Self.fileExtension)")
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(name) \(n).\(Self.fileExtension)")
            n += 1
        }
        try fm.copyItem(at: url, to: dest)
        for item in [dest] + (fm.enumerator(at: dest, includingPropertiesForKeys: nil)?.allObjects as? [URL] ?? []) {
            let mode = (try? fm.attributesOfItem(atPath: item.path)[.posixPermissions] as? Int) ?? 0o644
            try? fm.setAttributes([.posixPermissions: mode | 0o200], ofItemAtPath: item.path)
        }
        return ProjectBundle(url: dest)
    }

    private static func modified(_ url: URL) -> Date {
        let json = url.appendingPathComponent("project.json")
        return (try? json.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    public var projectURL: URL { url.appendingPathComponent("project.json") }

    public func load() throws -> Project {
        var project = try JSONDecoder().decode(Project.self, from: Data(contentsOf: projectURL))
        project.name = url.deletingPathExtension().lastPathComponent
        return project
    }

    public func save(_ project: Project) throws {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(project).write(to: projectURL, options: .atomic)
    }

    public func file(_ relative: String) -> URL { url.appendingPathComponent(relative) }

    public func makeClipFolder(id: UUID) throws -> (URL, String) {
        let rel = "clips/\(id.uuidString)"
        let dir = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, rel)
    }

    public func loadCursorLogs(for project: Project) -> [UUID: CursorLog] {
        var logs: [UUID: CursorLog] = [:]
        for clip in project.clips {
            guard let f = clip.cursorFile, let data = try? Data(contentsOf: file(f)),
                  let log = try? JSONDecoder().decode(CursorLog.self, from: data) else { continue }
            logs[clip.id] = log
        }
        return logs
    }

    public func backgroundImage(for project: Project) -> CIImage? {
        guard let rel = project.style.backgroundImage else { return nil }
        return CIImage(contentsOf: file(rel))
    }

    public func importBackground(from source: URL) throws -> String {
        let dir = url.appendingPathComponent("backgrounds")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(source.lastPathComponent)
        if !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return "backgrounds/\(source.lastPathComponent)"
    }

    public func removeOrphanedClips(keeping project: Project) {
        let keep = Set(project.clips.map(\.id.uuidString))
        let dir = url.appendingPathComponent("clips")
        for item in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !keep.contains(item) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(item))
        }
    }

    // MARK: - Audio

    public func importAudio(from source: URL) throws -> String {
        let dir = url.appendingPathComponent("audio")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent, ext = source.pathExtension
        var name = source.lastPathComponent
        var n = 2
        while FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path) {
            if Self.sameFile(dir.appendingPathComponent(name), source) { return "audio/\(name)" }
            name = "\(base) \(n).\(ext)"
            n += 1
        }
        try FileManager.default.copyItem(at: source, to: dir.appendingPathComponent(name))
        return "audio/\(name)"
    }

    private static func sameFile(_ a: URL, _ b: URL) -> Bool {
        let size: (URL) -> Int? = { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize }
        guard let sa = size(a), sa == size(b) else { return false }
        return (try? Data(contentsOf: a, options: .mappedIfSafe)) == (try? Data(contentsOf: b, options: .mappedIfSafe))
    }

    public func importedAudio() -> [String] {
        let dir = url.appendingPathComponent("audio")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { MusicLibrary.audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { "audio/\($0)" }
    }

    public func musicURL(for source: MusicSource) -> URL? {
        let found: URL? = switch source {
        case let .library(id): MusicLibrary.url(for: id)
        case let .file(rel): file(rel)
        }
        guard let found, FileManager.default.fileExists(atPath: found.path) else { return nil }
        return found
    }

    public func removeOrphanedAudio(keeping project: Project) {
        var keep = Set<String>()
        for clip in project.music { if case let .file(rel) = clip.source { keep.insert(rel) } }
        for rel in importedAudio() where !keep.contains(rel) { try? FileManager.default.removeItem(at: file(rel)) }
    }
}

public enum BackgroundLibrary {
    public static var directory: URL {
        if let dir = ProcessInfo.processInfo.environment["SCREENREC_LIBRARY_DIR"] { return URL(fileURLWithPath: dir) }
        return ProjectBundle.migrated(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                                      "Screen Recorder", to: "Slice").appendingPathComponent("Backgrounds")
    }

    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff", "webp"]

    public static func list() -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return items.filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    @discardableResult
    public static func add(_ source: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = source.deletingPathExtension().lastPathComponent
        let ext = source.pathExtension
        var dest = directory.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while FileManager.default.fileExists(atPath: dest.path) {
            dest = directory.appendingPathComponent("\(base) \(n).\(ext)")
            n += 1
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return dest
    }

    public static func remove(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
