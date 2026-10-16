//
//  CompositionBuilder.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/8/26.
//

import AVFoundation
import CoreImage

public enum CompositionBuilder {
    public struct Result {
        public let composition: AVComposition
        public let videoComposition: AVVideoComposition
        public let audioMix: AVAudioMix?
        public let audioLayout: AudioLayout
        public let packing: PreviewPacking?
    }

    public struct AudioLayout: Equatable, Sendable {
        public struct Music: Equatable, Sendable {
            public var clipID: UUID
            public var lane: Int
            public var trackID: CMPersistentTrackID
        }

        public var mic: CMPersistentTrackID?
        public var originalVoice: CMPersistentTrackID?
        public var screen: CMPersistentTrackID?
        public var joins: [Double]
        public var music: [Music]
        public var clicks: [CMPersistentTrackID] = []
        public var keys: [CMPersistentTrackID] = []

        public static let empty = AudioLayout(mic: nil, screen: nil, joins: [], music: [])

        public init(mic: CMPersistentTrackID?, originalVoice: CMPersistentTrackID? = nil, screen: CMPersistentTrackID?,
                    joins: [Double], music: [Music]) {
            self.mic = mic
            self.originalVoice = originalVoice
            self.screen = screen
            self.joins = joins
            self.music = music
        }
    }

    public static func audioMix(project: Project, layout: AudioLayout, originalVoice: Bool = false) -> AVAudioMix? {
        var params: [AVAudioMixInputParameters] = []
        let original = originalVoice && layout.originalVoice != nil
        for (id, volume) in [(layout.mic, original ? 0 : project.micVolume), (layout.originalVoice, original ? project.micVolume : 0),
                             (layout.screen, project.screenAudioVolume)] {
            guard let id else { continue }
            params.append(parameters(id, .joins(layout.joins, level: max(volume, 0))))
        }
        let lanes = project.musicLanes()
        for m in layout.music {
            let lane = lanes.first { $0.clipID == m.clipID && $0.lane == m.lane }
            params.append(parameters(m.trackID, lane?.envelope ?? .constant(0)))
        }
        let clickLevel = project.cursor.clickSound == .none ? 0 : min(max(project.cursor.clickSoundVolume, 0), 1)
        for id in layout.clicks { params.append(parameters(id, .constant(clickLevel))) }
        let keyLevel = project.keystrokes.sound == .none ? 0 : min(max(project.keystrokes.soundVolume, 0), 1)
        for id in layout.keys { params.append(parameters(id, .constant(keyLevel))) }
        guard !params.isEmpty else { return nil }
        let mix = AVMutableAudioMix()
        mix.inputParameters = params
        return mix
    }

    private static func parameters(_ trackID: CMPersistentTrackID, _ envelope: GainEnvelope) -> AVAudioMixInputParameters {
        let p = AVMutableAudioMixInputParameters()
        p.trackID = trackID
        let scale: CMTimeScale = 48000
        p.setVolume(Float(envelope.value(at: 0)), at: .zero)
        let points = envelope.points
        for (a, b) in zip(points, points.dropFirst()) where b.t > 0 && abs(a.gain - b.gain) > 1e-5 {
            let start = CMTime(seconds: max(a.t, 0), preferredTimescale: scale)
            let end = CMTime(seconds: b.t, preferredTimescale: scale)
            guard end > start else { continue }
            p.setVolumeRamp(fromStartVolume: Float(envelope.value(at: max(a.t, 0))), toEndVolume: Float(b.gain),
                            timeRange: CMTimeRange(start: start, end: end))
        }
        return p
    }

    public static func build(project: Project, bundle: ProjectBundle, state: RenderState,
                             renderSize: CGSize, fps: Int, preview: Bool = false, originalVoice: Bool = false) async throws -> Result {
        let comp = AVMutableComposition()
        guard let screenTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let cameraTrack = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let micTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let screenAudioTrack = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw NSError(domain: "Composition", code: 1) }

        // Load each clip's source tracks once. The assets must outlive the inserts (a track doesn't retain its asset).
        var assets: [AVURLAsset] = []
        func track(_ file: String?, _ type: AVMediaType) async throws -> AVAssetTrack? {
            guard let file else { return nil }
            let asset = AVURLAsset(url: bundle.file(file))
            assets.append(asset)
            return try await asset.loadTracks(withMediaType: type).first
        }
        typealias Sources = (screen: AVAssetTrack?, camera: AVAssetTrack?, mic: AVAssetTrack?, screenAudio: AVAssetTrack?,
                             originalMic: AVAssetTrack?)
        var sources: [Int: Sources] = [:]
        var enhanced = false
        for (i, clip) in project.clips.enumerated() {
            let voice = bundle.voiceFile(for: clip, settings: project.voice)
            let isEnhanced = voice != clip.micFile
            enhanced = enhanced || isEnhanced
            sources[i] = (try await track(clip.screenFile, .video), try await track(clip.cameraFile, .video),
                          try await track(voice, .audio), try await track(clip.screenAudioFile, .audio),
                          preview && isEnhanced ? try await track(clip.micFile, .audio) : nil)
        }
        let originalMicTrack = preview && enhanced
            ? comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) : nil

        let scale: CMTimeScale = 600
        var cursor = CMTime.zero
        var joins: [CMTime] = []
        var previous: Segment?
        for seg in project.segments {
            let src = sources[seg.clipIndex]!
            let from = CMTime(seconds: seg.sourceStart, preferredTimescale: scale)
            let len = CMTime(seconds: seg.duration, preferredTimescale: scale)
            try await insert(src.screen, from: from, duration: len, into: screenTrack, at: cursor)
            try await insert(src.camera, from: from, duration: len, into: cameraTrack, at: cursor)
            try await insert(src.mic, from: from, duration: len, into: micTrack, at: cursor)
            if let originalMicTrack { try await insert(src.originalMic, from: from, duration: len, into: originalMicTrack, at: cursor) }
            try await insert(src.screenAudio, from: from, duration: len, into: screenAudioTrack, at: cursor)
            if let p = previous, p.clipIndex != seg.clipIndex || abs(p.sourceEnd - seg.sourceStart) > 0.001 { joins.append(cursor) }
            previous = seg
            cursor = cursor + len
        }

        // A track with no media at all (e.g. no camera in any take) would make the composition invalid.
        var cameraID = cameraTrack.trackID
        if cameraTrack.segments.allSatisfy(\.isEmpty) {
            comp.removeTrack(cameraTrack)
            cameraID = kCMPersistentTrackID_Invalid
        }
        var layout = AudioLayout(mic: micTrack.trackID, originalVoice: originalMicTrack?.trackID, screen: screenAudioTrack.trackID,
                                 joins: joins.map(\.seconds), music: [])
        for track in [micTrack, screenAudioTrack] + [originalMicTrack].compactMap({ $0 }) where track.segments.allSatisfy(\.isEmpty) {
            comp.removeTrack(track)
            if track === micTrack { layout.mic = nil } else if track === screenAudioTrack { layout.screen = nil } else { layout.originalVoice = nil }
        }
        layout.music = await insertMusic(project: project, bundle: bundle, into: comp, end: cursor)
        let timeline = state.current().cursor
        layout.clicks = await insertClicks(project.cursor.clickSound, at: timeline.clicks.map(\.t), into: comp, end: cursor)
        layout.keys = await insertKeys(project.keystrokes.sound, hits: timeline.keyHits, into: comp, end: cursor)
        let audioMix = Self.audioMix(project: project, layout: layout, originalVoice: originalVoice)

        var packing: PreviewPacking?
        if preview {
            func size(_ track: AVAssetTrack?) async -> CGSize? {
                guard let track, let s = try? await track.load(.naturalSize) else { return nil }
                return CGSize(width: abs(s.width), height: abs(s.height))
            }
            var screens: [CGSize] = [], cameras: [CGSize?] = []
            for (i, clip) in project.clips.enumerated() {
                screens.append(await size(sources[i]?.screen) ?? clip.screenPixelSize)
                cameras.append(await size(sources[i]?.camera))
            }
            packing = PreviewPacking(screens: screens, cameras: cameras)
        }

        withExtendedLifetime(assets) {}
        let total = CMTimeRange(start: .zero, duration: cursor)
        let vc = AVMutableVideoComposition()
        vc.customVideoCompositorClass = ProjectCompositor.self
        vc.renderSize = packing?.canvas ?? renderSize
        vc.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
        vc.instructions = [ProjectInstruction(timeRange: total, screenTrackID: screenTrack.trackID,
                                              cameraTrackID: cameraID, state: state, packing: packing)]
        return Result(composition: comp, videoComposition: vc, audioMix: audioMix, audioLayout: layout, packing: packing)
    }

    private static func insertMusic(project: Project, bundle: ProjectBundle, into comp: AVMutableComposition,
                                    end: CMTime) async -> [AudioLayout.Music] {
        var out: [AudioLayout.Music] = []
        let scale: CMTimeScale = 48000
        for placement in project.musicPlacements where !placement.pieces.isEmpty {
            guard let url = bundle.musicURL(for: placement.source) else { continue }
            // Compressed formats (MP3) only cut at exact times with precise timing.
            let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
            do {
                guard let source = try await asset.loadTracks(withMediaType: .audio).first else { continue }
                let available = try await source.load(.timeRange)
                var tracks: [Int: AVMutableCompositionTrack] = [:]
                for piece in placement.pieces {
                    let at = CMTime(seconds: piece.at, preferredTimescale: scale)
                    let from = available.start + CMTime(seconds: piece.from, preferredTimescale: scale)
                    let len = CMTimeMinimum(CMTimeMinimum(CMTime(seconds: piece.length, preferredTimescale: scale), end - at),
                                            available.end - from)
                    guard len > .zero else { continue }
                    let track: AVMutableCompositionTrack
                    if let t = tracks[piece.lane] {
                        track = t
                    } else if let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                        track = t
                        tracks[piece.lane] = t
                        out.append(AudioLayout.Music(clipID: placement.id, lane: piece.lane, trackID: t.trackID))
                    } else { continue }
                    let trackEnd = track.timeRange.end
                    if at > trackEnd { track.insertEmptyTimeRange(CMTimeRange(start: trackEnd, end: at)) }
                    try track.insertTimeRange(CMTimeRange(start: from, duration: len), of: source, at: at)
                }
            } catch {
                NSLog("Music \(url.lastPathComponent) left out: \(error)")
            }
            withExtendedLifetime(asset) {}
        }
        return out
    }

    private static func insertClicks(_ sound: ClickSound, at times: [Double], into comp: AVMutableComposition,
                                     end: CMTime) async -> [CMPersistentTrackID] {
        guard let url = sound.url else { return [] }
        return await insertSounds([url], at: times.map { ($0, 0) }, into: comp, end: end, maxTracks: 4)
    }

    private static func insertKeys(_ sound: KeyboardSound, hits: [KeyHit], into comp: AVMutableComposition,
                                   end: CMTime) async -> [CMPersistentTrackID] {
        let picks = sound.picks(for: hits.map(\.kind))
        guard !picks.isEmpty else { return [] }
        return await insertSounds(sound.files, at: zip(hits, picks).map { ($0.t, $1) }, into: comp, end: end, maxTracks: 6)
    }

    private static func insertSounds(_ urls: [URL], at shots: [(t: Double, sound: Int)], into comp: AVMutableComposition,
                                     end: CMTime, maxTracks: Int) async -> [CMPersistentTrackID] {
        guard !shots.isEmpty else { return [] }
        let assets = urls.map { AVURLAsset(url: $0, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true]) }
        defer { withExtendedLifetime(assets) {} }
        var sources: [(track: AVAssetTrack, range: CMTimeRange)?] = []
        for asset in assets {
            if let track = try? await asset.loadTracks(withMediaType: .audio).first, let range = try? await track.load(.timeRange) {
                sources.append((track, range))
            } else {
                sources.append(nil)
            }
        }
        var tracks: [AVMutableCompositionTrack] = []
        for shot in shots {
            guard sources.indices.contains(shot.sound), let source = sources[shot.sound] else { continue }
            let at = CMTime(seconds: shot.t, preferredTimescale: 48000)
            let len = CMTimeMinimum(source.range.duration, end - at)
            guard at >= .zero, len > .zero else { continue }
            let track: AVMutableCompositionTrack
            if let free = tracks.first(where: { $0.timeRange.end <= at }) {
                track = free
            } else if tracks.count < maxTracks,
                      let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                tracks.append(t)
                track = t
            } else { continue }
            let trackEnd = track.timeRange.end
            if at > trackEnd { track.insertEmptyTimeRange(CMTimeRange(start: trackEnd, end: at)) }
            try? track.insertTimeRange(CMTimeRange(start: source.range.start, duration: len), of: source.track, at: at)
        }
        return tracks.map(\.trackID)
    }

    private static func insert(_ source: AVAssetTrack?, from: CMTime, duration: CMTime, into track: AVMutableCompositionTrack,
                               at start: CMTime) async throws {
        var used = CMTime.zero
        if let source {
            let range = try await source.load(.timeRange)
            let begin = range.start + from
            let len = CMTimeMinimum(range.end - begin, duration)
            if len > .zero {
                try track.insertTimeRange(CMTimeRange(start: begin, duration: len), of: source, at: start)
                used = len
            }
        }
        if used < duration {
            track.insertEmptyTimeRange(CMTimeRange(start: start + used, duration: duration - used))
        }
    }
}
