//
//  EditorModel+Transcript.swift
//  Slice
//
//  Created by rit3zh CX on 10/5/26.
//

import AppKit
import SliceCore
import SwiftUI

struct TranscriptWord: Identifiable, Equatable {
    let id: Int
    let clipIndex: Int
    let wordIndex: Int
    let word: Word
    let editedStart: Double?
    let editedEnd: Double?
    let startsParagraph: Bool
    var isCut: Bool { editedStart == nil }
}

struct TranscriptLine: Identifiable, Equatable {
    let id: Int
    let words: Range<Int>
    let startsParagraph: Bool

    static func lines(_ words: [TranscriptWord]) -> [TranscriptLine] {
        var out: [TranscriptLine] = []
        var start = 0, chars = 0
        for (i, w) in words.enumerated() {
            if i > start {
                let last = words[i - 1]
                let ending = last.word.text.last
                let breaks = w.startsParagraph
                    || w.word.start - last.word.end > 0.7
                    || (ending.map { ".?!".contains($0) } ?? false) && i - start >= 2
                    || (ending.map { ",;:".contains($0) } ?? false) && chars >= 24
                    || chars + 1 + w.word.text.count > 52
                if breaks {
                    out.append(TranscriptLine(id: out.count, words: start ..< i, startsParagraph: words[start].startsParagraph))
                    start = i
                    chars = 0
                }
            }
            chars += (chars > 0 ? 1 : 0) + w.word.text.count
        }
        if start < words.count {
            out.append(TranscriptLine(id: out.count, words: start ..< words.count, startsParagraph: words[start].startsParagraph))
        }
        return out
    }
}

extension EditorModel {
    static func loadTranscripts(bundle: ProjectBundle, project: Project) -> [UUID: Transcript] {
        var out: [UUID: Transcript] = [:]
        for clip in project.clips {
            guard let f = clip.transcriptFile, let data = try? Data(contentsOf: bundle.file(f)),
                  let t = try? JSONDecoder().decode(Transcript.self, from: data) else { continue }
            out[clip.id] = t
        }
        return out
    }

    var hasTranscript: Bool { !transcripts.isEmpty }

    private func checkSilentMics() {
        let files = project.clips.map { $0.speechAudioFile.map(bundle.file) }
        Task {
            let silent = await Task.detached {
                files.enumerated().compactMap { i, url in url.map(AudioCheck.isSilent) == true ? i + 1 : nil }
            }.value
            silentMicTakes = silent
        }
    }

    var untranscribedClips: [Clip] {
        project.clips.filter { $0.speechAudioFile != nil && transcripts[$0.id] == nil }
    }

    func refreshWordsAndCaptions() {
        var list: [TranscriptWord] = []
        for (ci, clip) in project.clips.enumerated() {
            guard let t = transcripts[clip.id] else { continue }
            for (wi, w) in t.words.enumerated() {
                let mid = (w.start + w.end) / 2
                let kept = !project.isCut(clipID: clip.id, local: mid)
                let es = kept ? project.editedPosition(clipIndex: ci, local: w.start) : nil
                let ee = kept ? project.editedPosition(clipIndex: ci, local: w.end) : nil
                let prevEnd = wi > 0 ? t.words[wi - 1].end : nil
                let paragraph = wi == 0 || (prevEnd.map { w.start - $0 > 1.5 } ?? true)
                list.append(TranscriptWord(id: list.count, clipIndex: ci, wordIndex: wi, word: w, editedStart: es,
                                           editedEnd: ee, startsParagraph: paragraph))
            }
        }
        words = list
        transcriptLines = TranscriptLine.lines(list)
        spokenWords = list.compactMap { w in w.editedStart.map { ($0, w.id) } }
        if list.isEmpty && hasTranscript { checkSilentMics() } else { silentMicTakes = [] }
        if let sel = wordSelection, sel.upperBound >= list.count { wordSelection = nil }
        captions = CaptionBuilder.captions(project: project, transcripts: transcripts,
                                           maxCharacters: previewSize.width > previewSize.height * 1.4 ? 48 : 30)
        renderState.update(captions: captions)
    }

    func lastSpokenWord(at t: Double) -> Int? {
        var lo = 0, hi = spokenWords.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if spokenWords[mid].start <= t + 0.02 { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 ? spokenWords[lo - 1].id : nil
    }

    func transcriptLine(containing wordID: Int) -> Int? {
        var lo = 0, hi = transcriptLines.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if transcriptLines[mid].words.lowerBound <= wordID { lo = mid + 1 } else { hi = mid }
        }
        return lo > 0 && transcriptLines[lo - 1].words.contains(wordID) ? lo - 1 : nil
    }

    // MARK: - Saving

    func save(_ transcript: Transcript, for clipID: UUID) throws {
        guard let i = project.clips.firstIndex(where: { $0.id == clipID }) else { return }
        let rel = (project.clips[i].screenFile as NSString).deletingLastPathComponent + "/transcript.json"
        try JSONEncoder().encode(transcript).write(to: bundle.file(rel), options: .atomic)
        transcripts[clipID] = transcript
        if project.clips[i].transcriptFile != rel {
            project.clips[i].transcriptFile = rel
        } else {
            refreshWordsAndCaptions()
        }
        saveNow()
    }

    func editWord(_ w: TranscriptWord, text: String) {
        let clipID = project.clips[w.clipIndex].id
        guard var t = transcripts[clipID], t.words.indices.contains(w.wordIndex) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        t.words[w.wordIndex].text = trimmed
        try? save(t, for: clipID)
    }

    // MARK: - Selection

    func selectWord(_ id: Int, extend: Bool) {
        if extend, let sel = wordSelection {
            wordSelection = min(sel.lowerBound, id) ... max(sel.upperBound, id)
        } else {
            wordSelection = id ... id
        }
        selection = nil
        if !extend, let start = words[id].editedStart { seek(to: start) }
    }

    func selectSentence(containing id: Int) {
        func endsSentence(_ i: Int) -> Bool { words[i].word.text.last.map { ".?!".contains($0) } ?? false }
        var lo = id
        while lo > 0, !endsSentence(lo - 1), !words[lo].startsParagraph { lo -= 1 }
        var hi = id
        while hi < words.count - 1, !endsSentence(hi), !words[hi + 1].startsParagraph { hi += 1 }
        wordSelection = lo ... hi
        selection = nil
    }

    var selectedWords: [TranscriptWord] {
        guard let sel = wordSelection else { return [] }
        return Array(words[sel.clamped(to: 0 ... max(words.count - 1, 0))])
    }

    var selectionHasKeptWords: Bool { selectedWords.contains { !$0.isCut } }
    var selectionHasCutWords: Bool { selectedWords.contains { $0.isCut } }

    // MARK: - Cutting

    func deleteSelectedWords() {
        let chosen = selectedWords.filter { !$0.isCut }
        guard !chosen.isEmpty else { return }
        var p = project
        var runs: [[TranscriptWord]] = []
        for w in chosen {
            if let last = runs.last?.last, last.clipIndex == w.clipIndex, last.wordIndex + 1 == w.wordIndex {
                runs[runs.count - 1].append(w)
            } else {
                runs.append([w])
            }
        }
        for run in runs.reversed() {
            let first = run.first!, last = run.last!
            let clipWords = transcripts[project.clips[first.clipIndex].id]?.words ?? []
            p.removeWords(clipIndex: first.clipIndex, words: clipWords, first: first.wordIndex, last: last.wordIndex)
        }
        guard !p.segments.isEmpty else { return }
        project = p
        wordSelection = nil
    }

    func restoreSelectedWords() {
        var p = project
        for w in selectedWords where w.isCut {
            let clip = project.clips[w.clipIndex]
            let mid = (w.word.start + w.word.end) / 2
            if let cut = p.cuts.first(where: { $0.clipID == clip.id && mid >= $0.start && mid < $0.end }) {
                p.restore(clipID: clip.id, from: cut.start, to: cut.end)
            }
        }
        project = p
    }

    // MARK: - Subtitle text

    func applySubtitleEdit(_ caption: Caption, text: String) {
        let refs = caption.words.map { ($0.clipIndex, $0.wordIndex) }
        var byClip: [UUID: Transcript] = [:]
        var originals: [Word] = []
        for (ci, wi) in refs {
            let id = project.clips[ci].id
            let t = byClip[id] ?? transcripts[id]
            guard let t, t.words.indices.contains(wi) else { return }
            byClip[id] = t
            originals.append(t.words[wi])
        }
        let edited = SubtitleEdit.apply(text, to: originals)
        guard edited != originals else { return }
        for ((ci, wi), w) in zip(refs, edited) {
            byClip[project.clips[ci].id]?.words[wi] = w
        }
        for (id, t) in byClip { try? save(t, for: id) }
    }

    func setSubtitleHidden(_ w: TranscriptWord, hidden: Bool) {
        let id = project.clips[w.clipIndex].id
        guard var t = transcripts[id], t.words.indices.contains(w.wordIndex) else { return }
        t.words[w.wordIndex].hidden = hidden ? true : nil
        try? save(t, for: id)
    }

    // MARK: - Undo

    func undo() {
        guard let prev = undoStack.popLast() else { return }
        redoStack.append(project)
        isRestoringHistory = true
        project = prev
        isRestoringHistory = false
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(project)
        isRestoringHistory = true
        project = next
        isRestoringHistory = false
    }

    // MARK: - Subtitles file

    func exportSRT() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.init(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = "\(project.name).srt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? SRT.make(captions).write(to: url, atomically: true, encoding: .utf8)
    }
}
