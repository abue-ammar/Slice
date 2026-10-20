//
//  EditorModel+Annotations.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import Foundation
import SliceCore

extension EditorModel {
    var selectedAnnotation: AnnotationBlock? {
        guard case let .annotation(id) = selection else { return nil }
        return project.annotations.first { $0.id == id }
    }

    /// While a mark is selected the preview shows the whole screen, so its box sits on what it was drawn over.
    var isEditingAnnotation: Bool { selectedAnnotation != nil && !isPlaying }

    var hasAnnotations: Bool { !project.annotations.isEmpty }

    /// The screen a mark was drawn over, in points, which its line widths and label sizes are measured against.
    func screenPoints(for block: AnnotationBlock) -> CGSize {
        let clip = project.clips.first { $0.id == block.clipID }
            ?? project.clips[safe: project.clipStarts.lastIndex { $0 <= block.start } ?? 0]
        let size = clip?.captureRect.size ?? .zero
        return size.width > 0 && size.height > 0 ? size : CGSize(width: 1512, height: 982)
    }

    /// Puts what each take drew on the timeline, once per take.
    func importAnnotations() {
        let next = Self.withImportedAnnotations(project, logs: loadCursorLogs())
        if next != project { project = next }
    }

    static func withImportedAnnotations(_ project: Project, logs: [UUID: CursorLog]) -> Project {
        var p = project
        for (i, clip) in project.clips.enumerated() where clip.annotationsImported != true {
            guard clip.device == nil, clip.cursorFile != nil else { continue }
            guard let log = logs[clip.id] else { continue }
            p.annotations += AnnotationBlock.imported(from: log, clipIndex: i, in: project)
            p.clips[i].annotationsImported = true
        }
        return p
    }

    func setAnnotationRange(_ id: UUID, start: Double, end: Double) {
        guard let i = project.annotations.firstIndex(where: { $0.id == id }) else { return }
        let b = project.annotations[i]
        var (s, e) = (start, end)
        if abs((e - s) - (b.end - b.start)) < 1e-9 {
            s = min(max(s, 0), max(duration - (b.end - b.start), 0))
            e = s + (b.end - b.start)
        } else {
            s = min(max(s, 0), e - Self.minBlock)
            e = min(max(e, s + Self.minBlock), duration)
        }
        project.annotations[i].start = s
        project.annotations[i].end = e
    }

    func updateAnnotation(_ id: UUID, _ change: (inout AnnotationBlock) -> Void) {
        guard let i = project.annotations.firstIndex(where: { $0.id == id }) else { return }
        var b = project.annotations[i]
        change(&b)
        project.annotations[i] = b
    }

    /// The mark under the playhead, else the next one along.
    func selectAnnotation(near t: Double) {
        let sorted = project.annotations.sorted { $0.start < $1.start }
        guard let b = sorted.last(where: { $0.isActive(at: t) }) ?? sorted.first(where: { $0.start > t }) ?? sorted.first else { return }
        selection = .annotation(b.id)
    }

    /// Onto a moment the mark shows fully, so it can be placed.
    func revealSelectedAnnotation() {
        guard let b = selectedAnnotation else { return }
        let drawn = b.drawsIn ? (b.mark.points.last?.t ?? 0) + 0.05 : 0.05
        guard b.drawnCount(at: time) < b.mark.points.count else { return }
        seek(to: min(b.start + drawn, b.start + (b.end - b.start) * 0.95))
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
