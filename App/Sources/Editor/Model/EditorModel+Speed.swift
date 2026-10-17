//
//  EditorModel+Speed.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import Foundation
import SliceCore

extension EditorModel {
    func setSpeed(_ speed: Double, for seg: Segment) {
        let keep = time >= seg.editedStart && time <= seg.editedEnd ? seg.local(at: time) : nil
        project.setSpeed(speed, for: seg)
        if let keep, let moved = project.editedTime(clipIndex: seg.clipIndex, local: keep) { seek(to: moved) }
    }

    var hasAutoSpeeds: Bool { project.speeds.contains(where: \.isAuto) }

    func speedUpQuietMoments(_ settings: QuietMoments.Settings) {
        let logs = cursorLogs
        guard project.clips.contains(where: { logs[$0.id] != nil }) else {
            note("These takes have no pointer recording to find quiet moments in.", symbol: "hare")
            return
        }
        let before = duration
        let found = QuietMoments.find(project: project, logs: logs, settings: settings)
        project.applyAutoSpeeds(found)
        let saved = before - duration
        let count = project.speeds.filter(\.isAuto).count
        note(count == 0 ? "Nothing quiet enough to speed up, so the recording is unchanged."
            : "Sped up \(count) quiet \(count == 1 ? "moment" : "moments"), \(Self.seconds(saved)) shorter. ⌘Z undoes it.",
            symbol: "hare")
    }

    func clearAutoSpeeds() {
        project.clearAutoSpeeds()
    }

    static func seconds(_ s: Double) -> String {
        s < 60 ? "\(Int(s.rounded()))s" : "\(Int(s / 60))m \(Int(s.truncatingRemainder(dividingBy: 60).rounded()))s"
    }
}
