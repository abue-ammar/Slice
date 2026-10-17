//
//  EditorModel+SmartZoom.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import Foundation
import SliceCore

extension EditorModel {
    static let autoZoomOnStopKey = "autoZoom.onStop"
    static var autoZoomOnStop: Bool { UserDefaults.standard.object(forKey: autoZoomOnStopKey) as? Bool ?? true }

    func smartZoomAfterRecording(clipIDs: Set<UUID>) {
        guard Self.autoZoomOnStop, !clipIDs.isEmpty else { return }
        runSmartZoom(only: clipIDs, quietWhenEmpty: true)
    }

    /// Holds the editor back (up to `limit`) until a fresh take's auto zooms are placed and its player has a frame, so
    /// it opens complete instead of on a black preview with the zooms landing a moment later.
    func readyAfterRecording(limit: Duration = .seconds(6)) async {
        let zooms = smartZoomTask, build = buildTask
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await zooms?.value
                await build?.value
            }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
    }

    func runSmartZoom(only: Set<UUID>? = nil, quietWhenEmpty: Bool = false) {
        guard smartZoomTask == nil else { return }
        let project = project, logs = cursorLogs, bundle = bundle
        guard project.clips.contains(where: { (only?.contains($0.id) ?? true) && logs[$0.id] != nil }) else {
            if !quietWhenEmpty { note("These takes have no pointer recording to find zoom moments in.") }
            return
        }
        smartZoomProgress = 0
        let throttle = ProgressThrottle()
        let report: @Sendable (Double) -> Void = { p in
            guard throttle.shouldReport(p) else { return }
            Task { @MainActor in
                if self.smartZoomProgress != nil { self.smartZoomProgress = p }
            }
        }
        smartZoomTask = Task { [weak self] in
            let found = await SmartZoom.detect(project: project, logs: logs, bundle: bundle, only: only, progress: report)
            guard let self else { return }
            defer {
                smartZoomTask = nil
                smartZoomProgress = nil
            }
            guard !Task.isCancelled else { return }
            smartDetections.merge(found) { $1 }
            let added = applySmartZoom(scope: Set(found.keys))
            if added > 0 {
                note(added == 1 ? "Added a zoom. ⌘Z undoes it." : "Added \(added) zooms. ⌘Z undoes them.")
            } else if !quietWhenEmpty {
                note("Nothing stood out enough to zoom into, so the recording is unchanged.")
            }
        }
    }

    func cancelSmartZoom() {
        smartZoomTask?.cancel()
        smartZoomTask = nil
        smartZoomProgress = nil
    }

    @discardableResult
    func applySmartZoom(scope: Set<UUID>, keepWhenEmpty: Bool = true) -> Int {
        let starts = project.clipStarts, lengths = project.clipEditedDurations
        let ranges = project.clips.indices.filter { scope.contains(project.clips[$0].id) }
            .map { starts[$0] ... starts[$0] + lengths[$0] }
        func inScope(_ z: ZoomBlock) -> Bool { ranges.contains { z.start < $0.upperBound && $0.lowerBound < z.end } }
        let planned = SmartZoom.plan(project: project, detections: smartDetections.filter { scope.contains($0.key) },
                                     settings: project.autoZoom).filter(inScope)
        guard !planned.isEmpty || !keepWhenEmpty else { return 0 }
        let kept = project.zoomBlocks.filter { !$0.isAuto || !inScope($0) }
        let fresh = planned.filter { s in !kept.contains { $0.start < s.end && s.start < $0.end } }
        project.zoomBlocks = kept + fresh
        if case let .zoom(id) = selection, !project.zoomBlocks.contains(where: { $0.id == id }) { selection = nil }
        return fresh.count
    }

    func smartZoomSettingsChanged() {
        smartReplan?.cancel()
        smartReplan = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard let self, !Task.isCancelled, smartZoomTask == nil else { return }
            let analysed = Set(smartDetections.keys)
            let logged = Set(project.clips.filter { self.cursorLogs[$0.id] != nil }.map(\.id))
            if logged.isSubset(of: analysed) {
                applySmartZoom(scope: analysed, keepWhenEmpty: false)
            } else if project.zoomBlocks.contains(where: \.isAuto) {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
                runSmartZoom(quietWhenEmpty: true)
            }
        }
    }

    func note(_ text: String, symbol: String = "sparkle.magnifyingglass") {
        noteSymbol = symbol
        smartZoomNote = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.smartZoomNote == text { self?.smartZoomNote = nil }
        }
    }
}
