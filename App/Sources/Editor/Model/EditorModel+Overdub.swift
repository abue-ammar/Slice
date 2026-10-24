//
//  EditorModel+Overdub.swift
//  Slice
//
//  Created by rit3zh CX on 10/24/26.
//

import SliceCore
import SwiftUI

extension EditorModel {
    /// The take a camera would be recorded over: the selected section's, or the one under the playhead.
    var overdubTarget: (id: UUID, index: Int)? {
        if case let .section(clipID, _) = selection, let i = project.clips.firstIndex(where: { $0.id == clipID }) {
            return (clipID, i)
        }
        guard let i = project.sourceTime(edited: time)?.clipIndex, project.clips.indices.contains(i) else { return nil }
        return (project.clips[i].id, i)
    }

    func recordCamera(over clipID: UUID) {
        guard overdub == nil, let i = project.clips.firstIndex(where: { $0.id == clipID }) else { return }
        pause()
        let clip = project.clips[i]
        // From the first moment of the take that's kept, so a trimmed start isn't sat through.
        let from = project.segments.first { $0.clipIndex == i }?.sourceStart ?? 0
        overdub = CameraOverdub(clip: clip, index: i, from: from, bundle: bundle) { [weak self] result in
            self?.overdubFinished(clipID: clipID, result)
        }
    }

    private func overdubFinished(clipID: UUID, _ result: CameraOverdub.Result?) {
        overdub = nil
        guard let result, let i = project.clips.firstIndex(where: { $0.id == clipID }) else { return }
        var p = project
        p.clips[i].cameraFile = result.cameraFile
        p.clips[i].cameraEnd = result.cameraEnd
        p.clips[i].cameraGlitches = nil
        if let mic = result.micFile {
            p.clips[i].micFile = mic
            p.clips[i].speech = nil
        }
        project = p
        saveNow()
        scanCameraGlitches()
        scanSpeech()
    }
}
