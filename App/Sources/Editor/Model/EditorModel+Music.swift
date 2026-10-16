//
//  EditorModel+Music.swift
//  Slice
//
//  Created by rit3zh CX on 10/6/26.
//

import AVFoundation
import SliceCore
import SwiftUI
import UniformTypeIdentifiers

extension EditorModel {
    static let libraryTracks = MusicLibrary.tracks()

    var focusedMusic: MusicClip? {
        if case let .music(id) = selection, let c = project.music.first(where: { $0.id == id }) { return c }
        let d = duration
        return project.music.first { $0.timelineRange(duration: d)?.contains(time) ?? false } ?? project.music.first
    }

    var selectedMusic: MusicClip? {
        guard case let .music(id) = selection else { return nil }
        return project.music.first { $0.id == id }
    }

    var hasSpeechAudio: Bool { project.clips.contains { $0.speechAudioFile != nil } }

    func musicURL(_ source: MusicSource) -> URL? { bundle.musicURL(for: source) }

    static func title(of source: MusicSource) -> String {
        switch source {
        case let .library(id): libraryTracks.first { $0.id == id }?.title ?? "Missing track"
        case let .file(rel): ((rel as NSString).lastPathComponent as NSString).deletingPathExtension
        }
    }

    private func quickInfo(_ source: MusicSource) async -> (duration: Double, loudness: Double?)? {
        guard let url = musicURL(source) else {
            audioError = "\(Self.title(of: source)) can't be found."
            return nil
        }
        if let s = AudioSummaries.shared.summaries[url] {
            audioError = nil
            return (s.duration, s.loudness)
        }
        let length = await Task.detached(priority: .userInitiated) { AudioAnalysis.duration(of: url) }.value
        guard let length, length > 0.1 else {
            audioError = "\(url.lastPathComponent) couldn't be read as audio."
            return nil
        }
        audioError = nil
        fillInLoudness(of: source, url: url)
        return (length, nil)
    }

    private func fillInLoudness(of source: MusicSource, url: URL) {
        Task { [weak self] in
            guard let s = await AudioSummaries.shared.load(url), let self,
                  project.music.contains(where: { $0.source == source && $0.sourceLoudness == nil }) else { return }
            var p = project
            for i in p.music.indices where p.music[i].source == source && p.music[i].sourceLoudness == nil {
                p.music[i].sourceLoudness = s.loudness
            }
            isRestoringHistory = true
            project = p
            isRestoringHistory = false
        }
    }

    func useMusic(_ source: MusicSource) async {
        guard duration > 0 else { return }
        if let current = focusedMusic, current.source == source { return }
        guard let info = await quickInfo(source) else { return }
        if let current = focusedMusic, let i = project.music.firstIndex(where: { $0.id == current.id }) {
            guard current.source != source else { return }
            replace(at: i, with: source, length: info.duration, loudness: info.loudness)
        } else {
            project.music.append(MusicClip(source: source, name: Self.title(of: source), start: 0, end: duration, toEnd: true,
                                           sourceDuration: info.duration, loops: true, sourceLoudness: info.loudness))
        }
    }

    func replaceMusic(_ id: UUID, with source: MusicSource) async {
        guard let info = await quickInfo(source), let i = project.music.firstIndex(where: { $0.id == id }) else { return }
        replace(at: i, with: source, length: info.duration, loudness: info.loudness)
    }

    private func replace(at i: Int, with source: MusicSource, length: Double, loudness: Double?) {
        var c = project.music[i]
        let end = c.nominalEnd(duration: duration)
        c.source = source
        c.name = Self.title(of: source)
        c.sourceDuration = length
        c.sourceLoudness = loudness
        c.offset = 0
        if !c.toEnd { c.end = end }
        if end - c.start > length + 0.01 { c.loops = true }
        project.music[i] = c
    }

    func addMusicClip(at t: Double) async {
        guard proposedRange(.music, at: t) != nil else { return }
        let source = focusedMusic?.source ?? Self.libraryTracks.first.map { .library($0.id) }
        guard let source, let info = await quickInfo(source),
              let range = proposedRange(.music, at: t) else { return }
        let start = range.lowerBound, end = range.upperBound
        let clip = MusicClip(source: source, name: Self.title(of: source), start: start, end: end,
                             toEnd: end >= duration - 0.01, sourceDuration: info.duration, loops: info.duration < end - start,
                             sourceLoudness: info.loudness)
        withAnimation(Theme.swap) {
            project.music.append(clip)
            selection = .music(clip.id)
        }
    }

    func importMusic(_ urls: [URL]) async {
        var first: MusicSource?
        let bundle = bundle
        for url in urls {
            let imported = await Task.detached(priority: .userInitiated) { () -> Result<String?, Error> in
                do {
                    let rel = try bundle.importAudio(from: url)
                    guard AudioAnalysis.duration(of: bundle.file(rel)) != nil else {
                        try? FileManager.default.removeItem(at: bundle.file(rel))
                        return .success(nil)
                    }
                    return .success(rel)
                } catch {
                    return .failure(error)
                }
            }.value
            switch imported {
            case let .success(rel?):
                if first == nil { first = .file(rel) }
            case .success(nil):
                audioError = "\(url.lastPathComponent) couldn't be read as audio."
            case let .failure(error):
                audioError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        importedAudio = bundle.importedAudio()
        if let first { await useMusic(first) }
    }

    func chooseMusicFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        panel.message = "Choose music to add. It's copied into the project, so moving the original won't break it."
        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }
        let urls = panel.urls
        Task { await importMusic(urls) }
    }

    func chooseReplacement(for id: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.message = "Choose the audio to play here instead."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let bundle = bundle
        Task {
            do {
                let rel = try await Task.detached(priority: .userInitiated) { try bundle.importAudio(from: url) }.value
                importedAudio = bundle.importedAudio()
                await replaceMusic(id, with: .file(rel))
            } catch {
                audioError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    func updateMusic(_ id: UUID, _ change: (inout MusicClip) -> Void) {
        guard let i = project.music.firstIndex(where: { $0.id == id }) else { return }
        change(&project.music[i])
    }

    func moveMusic(_ id: UUID, to start: Double) { project.moveMusic(id, to: start) }

    func trimMusic(_ id: UUID, start: Double? = nil, end: Double? = nil) { project.trimMusic(id, start: start, end: end) }

    func removeMusic(_ id: UUID) {
        project.music.removeAll { $0.id == id }
        if selection == .music(id) { selection = nil }
    }

    func removeAllMusic() {
        audition.stop()
        project.music.removeAll()
        if case .music = selection { selection = nil }
    }

    func toggleAudition(_ source: MusicSource) {
        if audition.playing == source {
            audition.stop()
            return
        }
        guard let url = musicURL(source) else {
            audioError = "\(Self.title(of: source)) can't be found."
            return
        }
        pause()
        audition.play(source, url: url)
    }
}

@MainActor
final class AudioSummaries: ObservableObject {
    static let shared = AudioSummaries()
    @Published private(set) var summaries: [URL: AudioSummary] = [:]
    private var loading: [URL: Task<AudioSummary?, Never>] = [:]

    func load(_ url: URL) async -> AudioSummary? {
        if let s = summaries[url] { return s }
        if let task = loading[url] { return await task.value }
        let task = Task.detached(priority: .userInitiated) { AudioAnalysis.summarize(url) }
        loading[url] = task
        let s = await task.value
        loading[url] = nil
        if let s { summaries[url] = s }
        return s
    }
}

@MainActor
final class MusicAudition: ObservableObject {
    @Published private(set) var playing: MusicSource?
    private let player = AVPlayer()
    private var fade: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?

    func play(_ source: MusicSource, url: URL) {
        fade?.cancel()
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.volume = 0
        player.play()
        playing = source
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item,
                                                             queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.playing = nil }
        }
        ramp(to: 0.8, over: 0.35)
    }

    func stop() {
        guard playing != nil else { return }
        playing = nil
        ramp(to: 0, over: 0.25) { [weak self] in self?.player.pause() }
    }

    private func ramp(to target: Float, over seconds: Double, then done: (() -> Void)? = nil) {
        fade?.cancel()
        let start = player.volume
        fade = Task { [weak self] in
            let steps = 12
            for i in 1 ... steps {
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
                guard let self, !Task.isCancelled else { return }
                let x = Float(i) / Float(steps)
                player.volume = start + (target - start) * x * x * (3 - 2 * x)
            }
            done?()
        }
    }
}
