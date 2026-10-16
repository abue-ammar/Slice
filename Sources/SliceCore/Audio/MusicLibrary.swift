//
//  MusicLibrary.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/1/26.
//

import Foundation

public enum MusicLibrary {
    public struct Track: Codable, Hashable, Identifiable {
        public var id: String
        public var title: String
        public var category: String
        public var file: String
        public var artist: String?
    }

    private struct Catalog: Codable {
        var categories: [String]?
        var tracks: [Track]
    }

    public static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "caf", "flac"]

    public static var directory: URL? {
        if let dir = ProcessInfo.processInfo.environment["SCREENREC_MUSIC_DIR"] { return URL(fileURLWithPath: dir) }
        return Bundle.main.url(forResource: "Music", withExtension: nil)
    }

    public static func tracks() -> [Track] {
        guard let dir = directory else { return [] }
        let catalog = (try? Data(contentsOf: dir.appendingPathComponent("catalog.json")))
            .flatMap { try? JSONDecoder().decode(Catalog.self, from: $0) }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [])
            .filter { audioExtensions.contains(($0 as NSString).pathExtension.lowercased()) }
        var out = (catalog?.tracks ?? []).filter { files.contains($0.file) }
        let listed = Set(out.map(\.file))
        for f in files.sorted() where !listed.contains(f) {
            let base = (f as NSString).deletingPathExtension
            out.append(Track(id: base, title: base.replacingOccurrences(of: "-", with: " ").capitalized, category: "Other", file: f))
        }
        return out
    }

    public static func categories(of tracks: [Track]) -> [String] {
        let order = ((try? Data(contentsOf: directory?.appendingPathComponent("catalog.json") ?? URL(fileURLWithPath: "/")))
            .flatMap { try? JSONDecoder().decode(Catalog.self, from: $0) })?.categories ?? []
        let used = tracks.map(\.category)
        var out = order.filter(used.contains)
        for c in used where !out.contains(c) { out.append(c) }
        return out
    }

    public static func url(for id: String) -> URL? {
        guard let dir = directory, let track = tracks().first(where: { $0.id == id }) else { return nil }
        return dir.appendingPathComponent(track.file)
    }
}
