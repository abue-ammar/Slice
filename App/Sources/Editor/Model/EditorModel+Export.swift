//
//  EditorModel+Export.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import Combine
import SliceCore
import SwiftUI

extension EditorModel {
    func importClips(_ urls: [URL]) async {
        var added: [Clip] = []
        for url in urls {
            do {
                added.append(try await ClipImporter.importVideo(url, into: bundle))
            } catch {
                transcribeError = "Couldn't import \(url.lastPathComponent): \(error.localizedDescription)"
            }
        }
        guard !added.isEmpty else { return }
        project.clips += added
        saveNow()
        scanSpeech()
    }

    func deleteClip(_ id: UUID) {
        guard canDeleteClip, let i = project.clips.firstIndex(where: { $0.id == id }) else { return }
        var p = project
        let start = p.clipStarts[i]
        let len = p.clipEditedDurations[i]
        let end = start + len
        func shift(_ s: Double, _ e: Double) -> (Double, Double)? {
            if e <= start { return (s, e) }
            if s >= end { return (s - len, e - len) }
            let ns = s < start ? s : start
            let ne = e > end ? e - len : start
            return ne - ns >= Self.minBlock ? (ns, ne) : nil
        }
        p.cameraBlocks = p.cameraBlocks.compactMap { b in shift(b.start, b.end).map { var b = b; (b.start, b.end) = $0; return b } }
        p.zoomBlocks = p.zoomBlocks.compactMap { b in shift(b.start, b.end).map { var b = b; (b.start, b.end) = $0; return b } }
        p.cuts.removeAll { $0.clipID == id }
        p.clips.remove(at: i)
        project = p
        saveNow()
    }

    func close() {
        stopExport()
        cancelTranscription()
        cancelSmartZoom()
        cancelVoice()
        cleanUpVoices()
        pause()
        audition.stop()
        saveNow()
        bundle.removeOrphanedClips(keeping: project)
        bundle.removeOrphanedAudio(keeping: project)
    }

    // MARK: - Export

    func startExport(to url: URL) {
        guard exportJob?.isRunning != true else { return }
        pause()
        let size = project.renderSize, settings = project.export
        let job = ExportJob(url: url, size: size, fps: settings.fps, hevc: settings.hevc,
                            bitRate: settings.bitRate(for: size), duration: project.duration)
        exportJob = job
        exportTask = Task { [weak self] in await self?.runExport(to: url, job: job.id) }
    }

    func stopExport() {
        exportTask?.cancel()
        exportTask = nil
        exportJob = nil
    }

    func dismissExport() {
        guard exportJob?.isRunning != true else { return }
        exportJob = nil
    }

    func runExport(to url: URL, job id: UUID) async {
        scanCameraGlitches()
        scanHoverMoments()
        scanSpeech()
        await glitchScan?.value
        await hoverScan?.value
        await speechScan?.value
        guard !Task.isCancelled else { return }
        saveNow()
        let throttle = ProgressThrottle()
        do {
            try await prepareVoiceForExport { [weak self] p in
                self?.update(id) { $0.note = "Enhancing voice… \(Int((p * 100).rounded(.down)))%" }
            }
            update(id) { $0.note = nil }
            try await Exporter.export(project: project, bundle: bundle, cursor: cursorTrack, captions: captions, to: url) { p in
                guard throttle.shouldReport(p) else { return }
                Task { @MainActor [weak self] in self?.exportProgressed(p, job: id) }
            }
            try Task.checkCancellation()
            let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
            update(id) { $0.progress = 1; $0.phase = .done(bytes: bytes) }
        } catch {
            if Task.isCancelled || error is CancellationError {
                try? FileManager.default.removeItem(at: url)
                return
            }
            update(id) { $0.phase = .failed(error.localizedDescription) }
        }
    }

    func exportProgressed(_ p: Double, job id: UUID) {
        update(id) { job in
            guard job.isRunning else { return }
            if job.phase == .preparing { job.renderStarted = Date() }
            job.progress = max(job.progress, p)
            job.phase = p >= 0.99 ? .finishing : .rendering
        }
    }

    func update(_ id: UUID, _ change: (inout ExportJob) -> Void) {
        guard var job = exportJob, job.id == id else { return }
        change(&job)
        exportJob = job
    }
}
