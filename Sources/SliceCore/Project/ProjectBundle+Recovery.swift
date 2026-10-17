//
//  ProjectBundle+Recovery.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/17/26.
//

import AVFoundation
import Foundation

/// A take that's recording keeps a note in its folder of the clip it will become, until the clip is in `project.json`.
/// If Slice never gets that far (it crashed or was quit, the Mac lost power) the note is still there next time, and the
/// take is put back: its files are written in fragments, so they play up to the last fragment that reached the disk.
extension ProjectBundle {
    /// How often a recording's files are made playable: the most a take cut off can lose.
    public static let fragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
    static let recordingNoteName = "recording.json"

    struct RecordingNote: Codable {
        var clip: Clip
        /// The Slice that was recording it; a note of this one's is a take still being recorded.
        var process: Int32
    }

    public func noteRecording(_ clip: Clip) throws {
        let note = RecordingNote(clip: clip, process: ProcessInfo.processInfo.processIdentifier)
        try JSONEncoder().encode(note).write(to: recordingNote(clip.id), options: .atomic)
    }

    public func clearRecordingNote(_ id: UUID) {
        try? FileManager.default.removeItem(at: recordingNote(id))
    }

    func recordingNote(_ id: UUID) -> URL {
        url.appendingPathComponent("clips/\(id.uuidString)/\(Self.recordingNoteName)")
    }

    func hasRecordingNote(folder: URL) -> Bool {
        FileManager.default.fileExists(atPath: folder.appendingPathComponent(Self.recordingNoteName).path)
    }

    /// Notes left by a Slice that's gone, in the order the takes were recorded.
    func interruptedNotes() -> [RecordingNote] {
        let dir = url.appendingPathComponent("clips")
        let fm = FileManager.default
        let folders = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let me = ProcessInfo.processInfo.processIdentifier
        return folders.compactMap { folder -> (Date, RecordingNote)? in
            let file = folder.appendingPathComponent(Self.recordingNoteName)
            guard let data = try? Data(contentsOf: file), let note = try? JSONDecoder().decode(RecordingNote.self, from: data),
                  note.process != me else { return nil }
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return (created, note)
        }
        .sorted { $0.0 < $1.0 }
        .map(\.1)
    }

    public var hasInterruptedTakes: Bool { !interruptedNotes().isEmpty }

    /// Adds every take that was cut off while recording back to the project, as far as its files play. Returns how many.
    @discardableResult
    public func recoverInterruptedTakes() async throws -> Int {
        let notes = interruptedNotes()
        guard !notes.isEmpty else { return 0 }
        var project = try load()
        var restored: [UUID] = []
        for note in notes {
            if project.clips.contains(where: { $0.id == note.clip.id }) {
                // Saved, and only the note was left behind.
                clearRecordingNote(note.clip.id)
            } else if let clip = await recoverTake(note.clip) {
                project.clips.append(clip)
                restored.append(clip.id)
            } else {
                // Nothing that plays: without its note the folder goes with the other unused ones.
                clearRecordingNote(note.clip.id)
            }
        }
        guard !restored.isEmpty else { return 0 }
        try save(project)
        restored.forEach(clearRecordingNote)
        return restored.count
    }

    /// The take as far as its screen recording plays; the camera, sound and pointer are kept where they can be read.
    public func recoverTake(_ planned: Clip) async -> Clip? {
        guard let screen = await playableRange(planned.screenFile, .video), screen.duration.seconds >= 0.5 else { return nil }
        var clip = planned
        clip.duration = screen.duration.seconds
        if await playableRange(planned.cameraFile, .video) == nil { clip.cameraFile = nil }
        if await playableRange(planned.micFile, .audio) == nil { clip.micFile = nil }
        if await playableRange(planned.screenAudioFile, .audio) == nil { clip.screenAudioFile = nil }
        if let cursor = planned.cursorFile,
           (try? JSONDecoder().decode(CursorLog.self, from: Data(contentsOf: file(cursor)))) == nil {
            clip.cursorFile = nil
        }
        return clip
    }

    private func playableRange(_ relative: String?, _ type: AVMediaType) async -> CMTimeRange? {
        guard let relative, FileManager.default.fileExists(atPath: file(relative).path) else { return nil }
        let asset = AVURLAsset(url: file(relative))
        guard let track = try? await asset.loadTracks(withMediaType: type).first,
              let range = try? await track.load(.timeRange), range.duration.seconds > 0 else { return nil }
        return range
    }

    /// Projects in `dir` (and `others`) with takes cut off while recording put back, newest first.
    public static func recoverInterruptedTakes(in dir: URL = defaultDirectory, adding others: [URL] = []) async -> [ProjectBundle] {
        var found: [ProjectBundle] = []
        for bundle in list(in: dir, adding: others) where bundle.hasInterruptedTakes {
            do {
                if try await bundle.recoverInterruptedTakes() > 0 { found.append(bundle) }
            } catch {
                NSLog("Couldn't recover takes in \(bundle.url.path): \(error)")
            }
        }
        return found
    }
}
