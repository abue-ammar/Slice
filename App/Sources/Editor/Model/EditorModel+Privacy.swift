//
//  EditorModel+Privacy.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import Foundation
import SliceCore

extension EditorModel {
    var redactRanges: [(id: UUID, start: Double, end: Double)] { project.redactions.map { ($0.id, $0.start, $0.end) } }

    var selectedRedaction: RedactBlock? {
        guard case let .redact(id) = selection else { return nil }
        return project.redactions.first { $0.id == id }
    }

    /// While a blur is selected the preview shows the whole screen, so its box can be placed on what it covers.
    var isEditingRedaction: Bool {
        if case .redact = selection, !isPlaying { return true }
        return false
    }

    func addRedaction(at t: Double) {
        guard let range = proposedRange(.blur, at: t) else { return }
        let size = CGSize(width: 0.3, height: 0.12)
        let center = cursorTrack.position(at: range.lowerBound) ?? CGPoint(x: 0.5, y: 0.5)
        let rect = RedactBlock.clamped(CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                                              width: size.width, height: size.height))
        let block = RedactBlock(start: range.lowerBound, end: range.upperBound, rect: rect)
        project.redactions.append(block)
        selection = .redact(block.id)
        seek(to: range.lowerBound)
    }

    func setRedactionRange(_ id: UUID, start: Double, end: Double) {
        guard let i = project.redactions.firstIndex(where: { $0.id == id }) else { return }
        let b = project.redactions[i]
        var (s, e) = (start, end)
        if abs((e - s) - (b.end - b.start)) < 1e-9 {
            s = min(max(s, 0), max(duration - (b.end - b.start), 0))
            e = s + (b.end - b.start)
        } else {
            s = min(max(s, 0), e - Self.minBlock)
            e = min(max(e, s + Self.minBlock), duration)
        }
        project.redactions[i].start = s
        project.redactions[i].end = e
        project.redactions[i].isAuto = false
    }

    func updateRedaction(_ id: UUID, _ change: (inout RedactBlock) -> Void) {
        guard let i = project.redactions.firstIndex(where: { $0.id == id }) else { return }
        var b = project.redactions[i]
        change(&b)
        b.rect = RedactBlock.clamped(b.rect)
        b.isAuto = false
        project.redactions[i] = b
    }

    func revealSelectedRedaction() {
        guard let b = selectedRedaction, !b.isActive(at: time) else { return }
        seek(to: b.start + min(0.05, (b.end - b.start) / 2))
    }

    // MARK: - Finding sensitive text

    func findSensitiveText() {
        guard privacyScanTask == nil, !project.clips.isEmpty else { return }
        let snapshot = project, bundle = bundle
        privacyScanProgress = 0
        let throttle = ProgressThrottle()
        let report: @Sendable (Double) -> Void = { p in
            guard throttle.shouldReport(p) else { return }
            Task { @MainActor [weak self] in
                if self?.privacyScanProgress != nil { self?.privacyScanProgress = p }
            }
        }
        privacyScanTask = Task { [weak self] in
            let found = try? await SensitiveTextScanner.scan(project: snapshot, bundle: bundle, progress: report)
            guard let self else { return }
            defer {
                privacyScanTask = nil
                privacyScanProgress = nil
            }
            guard !Task.isCancelled, let found else { return }
            guard project.segments == snapshot.segments else {
                note("The edit changed while scanning. Scan again to blur what's on screen now.", symbol: "eye.slash")
                return
            }
            project.redactions = project.redactions.filter { !$0.isAuto } + found
            if case let .redact(id) = selection, !project.redactions.contains(where: { $0.id == id }) { selection = nil }
            note(found.isEmpty ? "No emails, card numbers or keys found on screen."
                : found.count == 1 ? "Blurred 1 piece of sensitive text. ⌘Z undoes it."
                : "Blurred \(found.count) pieces of sensitive text. ⌘Z undoes them.", symbol: "eye.slash")
        }
    }

    func cancelSensitiveTextScan() {
        privacyScanTask?.cancel()
        privacyScanTask = nil
        privacyScanProgress = nil
    }
}
