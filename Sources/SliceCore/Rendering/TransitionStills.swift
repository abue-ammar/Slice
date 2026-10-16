//
//  TransitionStills.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/11/26.
//

import AVFoundation
import CoreImage
import Foundation

public struct TransitionStill: Hashable, Sendable {
    public var clipID: UUID
    public var tick: Int
    public var camera: Bool

    init(clipID: UUID, time: Double, camera: Bool) {
        self.clipID = clipID
        tick = Int((time * 10000).rounded())
        self.camera = camera
    }

    var time: Double { Double(tick) / 10000 }
}

extension TransitionWindow {
    func held(at t: Double) -> (incoming: Bool, segment: Segment, time: Double) {
        let incoming = t < time
        let seg = incoming ? next : previous
        return (incoming, seg, incoming ? seg.sourceStart : max(seg.sourceEnd - 1.0 / 60, seg.sourceStart))
    }
}

extension Project {
    public var transitionStills: Set<TransitionStill> {
        var out = Set<TransitionStill>()
        for w in transitionWindows {
            for side in [w.held(at: w.start), w.held(at: w.end)] {
                let clip = clips[side.segment.clipIndex]
                out.insert(TransitionStill(clipID: clip.id, time: side.time, camera: false))
                if clip.cameraFile != nil { out.insert(TransitionStill(clipID: clip.id, time: side.time, camera: true)) }
            }
        }
        return out
    }
}

/// Decodes the frames transitions hold, ahead of time. Decoding one frame from the middle of a recording means decoding
/// from the keyframe before it, which is far too slow to do while a transition plays.
public enum TransitionStills {
    public static func load(_ stills: Set<TransitionStill>, project: Project, bundle: ProjectBundle) async -> [TransitionStill: CIImage] {
        var out: [TransitionStill: CIImage] = [:]
        let byFile = Dictionary(grouping: stills) { still -> String? in
            guard let clip = project.clips.first(where: { $0.id == still.clipID }) else { return nil }
            return still.camera ? clip.cameraFile : clip.screenFile
        }
        for (file, wanted) in byFile {
            guard let file else { continue }
            let asset = AVURLAsset(url: bundle.file(file))
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let range = try? await track.load(.timeRange) else { continue }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = false
            for still in wanted {
                let at = CMTimeMinimum(range.start + CMTime(seconds: still.time, preferredTimescale: 600),
                                       range.end - CMTime(value: 1, timescale: 600))
                generator.requestedTimeToleranceBefore = .zero
                generator.requestedTimeToleranceAfter = .zero
                var image = try? await generator.image(at: at).image
                if image == nil {
                    generator.requestedTimeToleranceBefore = .positiveInfinity
                    image = try? await generator.image(at: at).image
                }
                if let image { out[still] = CIImage(cgImage: image) }
            }
        }
        return out
    }
}
