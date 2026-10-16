//
//  EditorModel+Voice.swift
//  Slice
//
//  Created by rit3zh CX on 10/6/26.
//

import SliceCore
import SwiftUI

@MainActor
final class VoiceModelStore: ObservableObject {
    static let shared = VoiceModelStore()

    enum State: Equatable {
        case notInstalled
        case downloading(received: Int64, total: Int64)
        case installed
        case failed(String)
    }

    @Published private(set) var state: State
    private var task: Task<Void, Never>?

    private init() { state = VoiceModel.isInstalled ? .installed : .notInstalled }

    var isInstalled: Bool { state == .installed }
    var isDownloading: Bool { if case .downloading = state { true } else { false } }

    func download() {
        guard task == nil else { return }
        state = .downloading(received: 0, total: VoiceModel.downloadBytes)
        let throttle = ProgressThrottle()
        task = Task {
            do {
                try await VoiceModel.install { received, total in
                    guard throttle.shouldReport(Double(received) / Double(max(total, 1))) else { return }
                    Task { @MainActor [weak self] in
                        guard let self, self.isDownloading else { return }
                        self.state = .downloading(received: received, total: total)
                    }
                }
                state = .installed
            } catch is CancellationError {
                state = .notInstalled
            } catch {
                state = .failed(error.localizedDescription)
            }
            task = nil
        }
    }

    func cancel() { task?.cancel() }

    func remove() {
        try? VoiceModel.remove()
        state = VoiceModel.isInstalled ? .installed : .notInstalled
    }
}

extension EditorModel {
    private static let denoiseShare = 0.85

    var hasMicrophone: Bool { project.clips.contains { $0.micFile != nil } }

    var voicePending: [Clip] { project.clips.filter { !bundle.hasVoice(for: $0, settings: project.voice) } }

    var needsVoiceModel: Bool { voicePending.contains { !isDenoised($0) } }

    private func isDenoised(_ clip: Clip) -> Bool {
        guard let file = bundle.denoisedVoiceFile(for: clip) else { return true }
        return FileManager.default.fileExists(atPath: bundle.file(file).path)
    }

    func setVoiceEnhancement(_ on: Bool) {
        if on, needsVoiceModel, !VoiceModelStore.shared.isInstalled {
            showVoiceModelSheet = true
            return
        }
        project.voice.enhance = on
    }

    func voiceModelInstalled() {
        voiceError = nil
        if project.voice.enhance { scheduleVoice(rebuildIfReady: true) } else { project.voice.enhance = true }
    }

    func voiceSettingsChanged(from old: VoiceSettings) {
        voiceError = nil
        guard project.voice.enhance else {
            cancelVoice()
            hearOriginalVoice = false
            if old.enhance { Task { await rebuild() } }
            return
        }
        let settingsChanged = old != project.voice
        scheduleVoice(after: settingsChanged && old.enhance ? .milliseconds(350) : .zero, rebuildIfReady: settingsChanged)
    }

    func scheduleVoice(after delay: Duration = .zero, rebuildIfReady: Bool) {
        voiceTask?.cancel()
        voiceTask = nil
        voicePlan = [:]
        guard project.voice.enhance else {
            voiceProgress = nil
            return
        }
        let pending = voicePending
        guard !pending.isEmpty else {
            voiceProgress = nil
            if rebuildIfReady { Task { await rebuild() } }
            return
        }
        if pending.contains(where: { !isDenoised($0) }), !VoiceModel.isInstalled {
            voiceProgress = nil
            voiceError = "The voice model isn't on this Mac. Download it to enhance \(pending.count == 1 ? "this take" : "these takes")."
            if rebuildIfReady { Task { await rebuild() } }
            return
        }
        let total = pending.reduce(0) { $0 + max($1.duration, 0.1) }
        voicePlan = Dictionary(uniqueKeysWithValues: pending.map { ($0.id, max($0.duration, 0.1) / total) })
        voiceParts = [:]
        voiceProgress = 0
        let settings = project.voice
        voiceTask = Task(priority: .utility) { [weak self] in
            try await Task.sleep(for: delay)
            try await self?.makeVoices(pending, settings: settings)
        }
    }

    private func makeVoices(_ clips: [Clip], settings: VoiceSettings) async throws {
        do {
            for clip in clips {
                try Task.checkCancellation()
                let split = isDenoised(clip) ? 0 : Self.denoiseShare
                if split > 0 {
                    let job = denoiseJob(for: clip)
                    do {
                        try await job.value
                    } catch {
                        if denoiseJobs[clip.id] == job { denoiseJobs[clip.id] = nil }
                        throw error
                    }
                    if denoiseJobs[clip.id] == job { denoiseJobs[clip.id] = nil }
                }
                try Task.checkCancellation()
                let bundle = bundle, id = clip.id
                try await VoiceEnhancer.prepare(clip, settings: settings, bundle: bundle) { p in
                    Task { @MainActor [weak self] in self?.voiceReported(id, split + p * (1 - split)) }
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            voiceError = "Couldn't enhance the voice. \(error.localizedDescription)"
            voiceProgress = nil
            voicePlan = [:]
            throw error
        }
        voiceProgress = nil
        voicePlan = [:]
        if project.voice == settings { await rebuild() }
    }

    private func denoiseJob(for clip: Clip) -> Task<Void, Error> {
        if let job = denoiseJobs[clip.id] { return job }
        let bundle = bundle, id = clip.id, share = Self.denoiseShare
        let job = Task.detached(priority: .utility) { [weak self] in
            try await VoiceEnhancer.denoiseIfNeeded(clip, bundle: bundle) { p in
                Task { @MainActor [weak self] in self?.voiceReported(id, p * share) }
            }
        }
        denoiseJobs[clip.id] = job
        return job
    }

    private func voiceReported(_ id: UUID, _ p: Double) {
        guard voicePlan[id] != nil, voiceProgress != nil else { return }
        voiceParts[id] = max(voiceParts[id] ?? 0, p)
        let total = voicePlan.reduce(0) { $0 + $1.value * (voiceParts[$1.key] ?? 0) }
        exportVoiceProgress?(total)
        if Int(total * 100) != Int((voiceProgress ?? 0) * 100) { voiceProgress = total }
    }

    func cancelVoice() {
        voiceTask?.cancel()
        voiceTask = nil
        for job in denoiseJobs.values { job.cancel() }
        denoiseJobs = [:]
        voicePlan = [:]
        voiceProgress = nil
    }

    func prepareVoiceForExport(progress: @escaping (Double) -> Void) async throws {
        guard project.voice.enhance, !voicePending.isEmpty else { return }
        if needsVoiceModel, !VoiceModel.isInstalled {
            throw ExportVoiceError("Voice enhancement is on, but its model isn't on this Mac. Download it in the Audio panel, or turn enhancement off.")
        }
        exportVoiceProgress = progress
        defer { exportVoiceProgress = nil }
        progress(0)
        scheduleVoice(rebuildIfReady: false)
        while let task = voiceTask {
            do {
                try await task.value
                break
            } catch is CancellationError {
                try Task.checkCancellation()
                if voiceTask == task { break }
            }
        }
        try Task.checkCancellation()
        guard voicePending.isEmpty else {
            throw ExportVoiceError(voiceError ?? "The enhanced voice couldn't be made.")
        }
    }

    func cleanUpVoices() {
        for clip in project.clips { bundle.removeOtherVoices(for: clip, keeping: project.voice) }
    }
}

struct ExportVoiceError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
