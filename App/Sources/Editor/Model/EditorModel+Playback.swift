//
//  EditorModel+Playback.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import AVFoundation
import Combine
import SliceCore
import SwiftUI

extension EditorModel {
    func rebuild() async {
        buildGeneration &+= 1
        let generation = buildGeneration
        do {
            let fps = min(max(project.clips.compactMap(\.frameRate).max() ?? 60, 30), 120)
            let snapshot = project
            let built = try await CompositionBuilder.build(project: snapshot, bundle: bundle, state: renderState,
                                                           renderSize: .zero, fps: fps, preview: true,
                                                           originalVoice: hearOriginalVoice)
            // Quick changes (clicking through sounds) start builds faster than they finish; only the newest is used.
            guard generation == buildGeneration else { return }
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            item.audioMix = built.audioMix
            audioLayout = built.audioLayout
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: Self.outputAttributes)
            item.add(output)

            // Where playback is now (it carried on while this built). The new item starts at zero, so it's held still
            // and marked as seeking until it's there: otherwise the playhead and the preview briefly read zero and
            // jump to the start, and the sound blips from the beginning.
            let resume = min(liveTime, max(duration - 0.05, 0))
            isSeeking = true
            clock.time = resume
            if player.rate != 0 { player.rate = 0 }
            invalidatePreview()
            player.replaceCurrentItem(with: item)
            if project.music != snapshot.music || project.audio != snapshot.audio || project.micVolume != snapshot.micVolume
                || project.screenAudioVolume != snapshot.screenAudioVolume
                || project.cursor.clickSoundVolume != snapshot.cursor.clickSoundVolume
                || project.keystrokes.soundVolume != snapshot.keystrokes.soundVolume
                || project.clips.map(\.speech) != snapshot.clips.map(\.speech) {
                updateAudioMix()
            }
            await player.seek(to: CMTime(seconds: resume, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            // A newer build swapped in meanwhile and finishes the job.
            guard generation == buildGeneration else { return }
            videoOutput = output
            packing = built.packing
            previewDriver.setSource(output, packing: built.packing)
            isSeeking = false
            if isPlaying, player.currentItem === item {
                player.volume = 0
                player.rate = playbackRate
                fadeVolume(to: 1, over: 0.08)
            }
            chaseSeek()
            invalidatePreview()
            prerollIfIdle()
        } catch {
            NSLog("Composition failed: \(error)")
        }
    }

    func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    func play() {
        if time >= duration - 0.05 { seek(to: 0) }
        audition.stop()
        player.volume = 0
        player.rate = playbackRate
        clock.isPlaying = true
        fadeVolume(to: 1, over: 0.08)
        updateRenderOptions()
    }

    /// `settle` lands on the frame on screen; a scrub skips it because its own seek follows straight away.
    func pause(settle: Bool = true) {
        volumeFade?.cancel()
        guard player.rate != 0 || clock.isPlaying else { return }
        let shown = previewDriver.shownTime, now = player.currentTime().seconds
        player.pause()
        player.volume = 1
        clock.isPlaying = false
        if settle { seek(to: shown.isFinite && abs(shown - now) < 0.3 ? shown : now) }
        updateRenderOptions()
    }

    /// Until a seek lands the player still reports where it was, so the playhead keeps to the target meanwhile.
    var liveTime: Double {
        guard isPlaying, !seekPending else { return time }
        let t = player.currentTime().seconds
        return min(max(t.isFinite ? t : time, 0), duration)
    }

    func fadeVolume(to target: Float, over seconds: Double) {
        volumeFade?.cancel()
        let start = player.volume
        volumeFade = Task { @MainActor [weak self] in
            let steps = 10
            for i in 1 ... steps {
                try? await Task.sleep(for: .seconds(seconds / Double(steps)))
                guard let self, !Task.isCancelled else { return }
                player.volume = start + (target - start) * Float(i) / Float(steps)
            }
        }
    }

    func seek(to t: Double) {
        let clamped = min(max(t.isFinite ? t : 0, 0), duration)
        clock.time = clamped
        seekTarget = clamped
        if !isSeeking { chaseSeek() }
        if case .zoom = selection { updateRenderOptions() } else { invalidatePreview() }
    }

    func scrub(to t: Double) {
        if !isScrubbing {
            isScrubbing = true
            resumeAfterScrub = isPlaying
            if isPlaying { pause(settle: false) }
        }
        seek(to: t)
    }

    func endScrub() {
        guard isScrubbing else { return }
        isScrubbing = false
        if resumeAfterScrub, time < duration - 0.05 { play() }
        resumeAfterScrub = false
    }

    var seekPending: Bool { isSeeking || seekTarget != nil }

    func chaseSeek() {
        guard let target = seekTarget else {
            if player.rate != 0 { invalidatePreview() }
            return
        }
        seekTarget = nil
        isSeeking = true
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isSeeking = false
                self.chaseSeek()
                self.prerollIfIdle()
            }
        }
    }

    func prerollIfIdle() {
        guard !isSeeking, seekTarget == nil, player.rate == 0, player.status == .readyToPlay,
              player.currentItem?.status == .readyToPlay else { return }
        player.preroll(atRate: playbackRate)
    }

    func loadTransitionStills() {
        let wanted = renderState.missing(project.transitionStills)
        guard !wanted.isEmpty else { return }
        let project = project, bundle = bundle, state = renderState
        Task.detached(priority: .userInitiated) { [weak self] in
            state.add(stills: await TransitionStills.load(wanted, project: project, bundle: bundle))
            await MainActor.run { self?.invalidatePreview() }
        }
    }

    func invalidatePreview() {
        previewDriver.setPlayback(playing: player.rate != 0, seeking: seekPending, time: time, duration: duration)
    }

    var isEditingZoomFocus: Bool {
        if case .zoom = selection, !isPlaying { return true }
        return false
    }

    var selectedZoom: ZoomBlock? {
        guard case let .zoom(id) = selection else { return nil }
        return project.zoomBlocks.first { $0.id == id }
    }

    func updateRenderOptions() {
        var onCanvas = false
        if isEditingZoomFocus, let z = selectedZoom, z.kind != .liquidGlass { onCanvas = !(z.start ..< z.end).contains(time) }
        if onCanvas != aimsOnCanvas { aimsOnCanvas = onCanvas }
        renderState.update(options: FrameRenderer.Options(ignoreZoom: onCanvas || isEditingRedaction || isEditingSpotlight))
        invalidatePreview()
    }

    func revealSelectedLens() {
        guard let z = selectedZoom, z.kind == .liquidGlass, !(z.start ... z.end).contains(time) else { return }
        seek(to: (z.start + z.end) / 2)
    }
}
