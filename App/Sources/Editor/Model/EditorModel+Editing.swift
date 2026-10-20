//
//  EditorModel+Editing.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import Combine
import SliceCore
import SwiftUI

extension EditorModel {
    func scheduleResmooth() {
        resmoothTask?.cancel()
        let snapshot = project, logs = cursorLogs, previous = cursorTrack.motion
        resmoothTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            let track = await Task.detached(priority: .userInitiated) {
                CursorTrack(project: snapshot, logs: logs,
                            motion: CursorMotion(project: snapshot, logs: logs, reusing: previous))
            }.value
            guard let self, !Task.isCancelled, Self.footage(self.project.clips) == Self.footage(snapshot.clips),
                  self.project.clips.map(\.hoverMoments) == snapshot.clips.map(\.hoverMoments),
                  self.project.cuts == snapshot.cuts, self.project.speeds == snapshot.speeds,
                  self.project.cursor.smoothing == snapshot.cursor.smoothing
            else { return }
            self.cursorTrack = track
            self.renderState.update(project: self.project, cursor: track)
            self.invalidatePreview()
        }
    }

    static func footage(_ clips: [Clip]) -> [Clip] {
        clips.map { c in
            var c = c
            c.cameraGlitches = nil
            c.hoverMoments = nil
            c.speech = nil
            c.transcriptFile = nil
            c.annotationsImported = nil
            return c
        }
    }

    func loadCursorLogs() -> [UUID: CursorLog] {
        let ids = Set(project.clips.map(\.id))
        var logs = cursorLogs.filter { ids.contains($0.key) }
        let missing = project.clips.filter { $0.cursorFile != nil && logs[$0.id] == nil }
        guard !missing.isEmpty else { return logs }
        var p = project
        p.clips = missing
        logs.merge(bundle.loadCursorLogs(for: p)) { $1 }
        return logs
    }

    func projectChanged(from old: Project) {
        if !isRestoringHistory, Date().timeIntervalSince(lastChangeAt) > 0.8 {
            undoStack.append(old)
            if undoStack.count > 100 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        lastChangeAt = Date()
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        // Background scans only add notes about a take (glitches, hover moments, speech) and transcribing only adds a
        // transcript: none of that changes what the player plays, so it never rebuilds it.
        let clipsChanged = old.clips != project.clips
        let footageChanged = clipsChanged && Self.footage(old.clips) != Self.footage(project.clips)
        let editChanged = footageChanged || old.cuts != project.cuts || old.speeds != project.speeds
        if editChanged || old.subtitles != project.subtitles
            || (clipsChanged && old.clips.map(\.transcriptFile) != project.clips.map(\.transcriptFile)) {
            refreshWordsAndCaptions()
        }
        if old.style.backgroundImage != project.style.backgroundImage {
            renderState.update(backgroundImage: bundle.backgroundImage(for: project))
        }
        if editChanged {
            resmoothTask?.cancel()
            cursorLogs = loadCursorLogs()
            let motion = CursorMotion(project: project, logs: cursorLogs, reusing: cursorTrack.motion)
            cursorTrack = CursorTrack(project: project, logs: cursorLogs, motion: motion)
            renderState.update(project: project, cursor: cursorTrack)
            buildTask = Task { await rebuild() }
        } else if old.cursor.smoothing != project.cursor.smoothing
            || (clipsChanged && old.clips.map(\.hoverMoments) != project.clips.map(\.hoverMoments)) {
            renderState.update(project: project)
            scheduleResmooth()
        } else {
            renderState.update(project: project)
        }
        if old.transitionWindows != project.transitionWindows { loadTransitionStills() }
        if !editChanged {
            if old.musicPlacements != project.musicPlacements || old.cursor.clickSound != project.cursor.clickSound
                || old.keystrokes.sound != project.keystrokes.sound {
                scheduleMusicRebuild()
            } else if old.music != project.music || old.audio != project.audio || old.micVolume != project.micVolume
                || old.screenAudioVolume != project.screenAudioVolume
                || old.cursor.clickSoundVolume != project.cursor.clickSoundVolume
                || old.keystrokes.soundVolume != project.keystrokes.soundVolume
                || (clipsChanged && old.clips.map(\.speech) != project.clips.map(\.speech)) {
                updateAudioMix()
            }
        }
        if old.autoZoom != project.autoZoom, !isRestoringHistory { smartZoomSettingsChanged() }
        if old.device3D.model != project.device3D.model || (project.device3D.enabled && !old.device3D.enabled) { warmUp3D() }
        if old.voice != project.voice || (clipsChanged && old.clips.map(\.micFile) != project.clips.map(\.micFile)) {
            voiceSettingsChanged(from: old.voice)
        }
        if case .zoom = selection { updateRenderOptions() }
        invalidatePreview()
        scheduleSave()
    }

    func updateAudioMix() {
        player.currentItem?.audioMix = CompositionBuilder.audioMix(project: project, layout: audioLayout,
                                                                   originalVoice: hearOriginalVoice)
    }

    func scheduleMusicRebuild() {
        musicRebuild?.cancel()
        musicRebuild = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, !Task.isCancelled else { return }
            await rebuild()
        }
    }

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [bundle, project] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            try? bundle.save(project)
        }
    }

    func saveNow() {
        saveTask?.cancel()
        try? bundle.save(project)
    }

    func appendRecordedClips(from recorded: Project) {
        let warm = !project.hasDeviceRecording && recorded.hasDeviceRecording
        project.clips = recorded.clips
        importAnnotations()
        if warm { warmUp3D() }
        saveNow()
        scanCameraGlitches()
        scanHoverMoments()
        scanSpeech()
    }

    func scanCameraGlitches() {
        let todo = project.clips.filter { $0.cameraFile != nil && $0.cameraGlitches == nil }
        guard !todo.isEmpty, glitchScan == nil else { return }
        let bundle = bundle
        glitchScan = Task {
            defer { glitchScan = nil }
            var found: [UUID: [TimeSpan]] = [:]
            for clip in todo {
                guard let file = clip.cameraFile else { continue }
                found[clip.id] = (try? await CameraGlitchDetector.scan(bundle.file(file))) ?? []
            }
            var p = project
            for i in p.clips.indices { if let g = found[p.clips[i].id] { p.clips[i].cameraGlitches = g } }
            isRestoringHistory = true
            project = p
            isRestoringHistory = false
        }
    }

    func scanHoverMoments() {
        let todo = project.clips.filter { $0.hasEditableCursor && $0.hoverMoments == nil }
        guard !todo.isEmpty, hoverScan == nil else { return }
        let bundle = bundle, logs = cursorLogs
        hoverScan = Task {
            defer { hoverScan = nil }
            var found: [UUID: [Double]] = [:]
            for clip in todo {
                guard let log = logs[clip.id] else { continue }
                found[clip.id] = (try? await HoverDetector.scan(video: bundle.file(clip.screenFile), log: log,
                                                               pointSize: clip.captureRect.size)) ?? []
            }
            var p = project
            for i in p.clips.indices { if let h = found[p.clips[i].id] { p.clips[i].hoverMoments = h } }
            isRestoringHistory = true
            project = p
            isRestoringHistory = false
        }
    }

    func scanSpeech() {
        let todo = project.clips.filter { $0.speechAudioFile != nil && $0.speech == nil }
        guard !todo.isEmpty, speechScan == nil else { return }
        let bundle = bundle
        speechScan = Task {
            defer { speechScan = nil }
            var found: [UUID: [TimeSpan]] = [:]
            for clip in todo {
                guard let file = clip.speechAudioFile else { continue }
                let url = bundle.file(file)
                found[clip.id] = await Task.detached(priority: .utility) { AudioAnalysis.speech(in: url) }.value
            }
            var p = project
            for i in p.clips.indices { if let s = found[p.clips[i].id] { p.clips[i].speech = s } }
            isRestoringHistory = true
            project = p
            isRestoringHistory = false
            updateAudioMix()
        }
    }

    var isScanningSpeech: Bool { speechScan != nil }

    func reloadAfterRecording() {
        buildTask = Task { await rebuild() }
    }

    // MARK: - Backgrounds

    func useBackground(_ libraryURL: URL) {
        do {
            project.style.backgroundImage = try bundle.importBackground(from: libraryURL)
        } catch {
            NSLog("Background import failed: \(error)")
        }
    }

    func useGradientBackground() { project.style.backgroundImage = nil }

    @discardableResult
    func addToLibrary(_ urls: [URL]) -> [URL] {
        let added = urls.compactMap { try? BackgroundLibrary.add($0) }
        if let last = added.last { useBackground(last) }
        return added
    }
}
