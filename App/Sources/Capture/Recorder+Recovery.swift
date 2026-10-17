//
//  Recorder+Recovery.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import AppKit
import SliceCore

extension Recorder {
    /// Leaves a note of the take in its folder and saves its pointer every couple of seconds, so if Slice stops before
    /// the take is saved (a crash, a quit, the Mac losing power) it comes back next launch with its pointer too.
    func keepRecoverable(_ writer: TakeWriter, captureRect: CGRect) {
        try? bundle.noteRecording(writer.planned(captureRect: captureRect))
        cursorSaver?.invalidate()
        let timer = Timer(timeInterval: ProjectBundle.fragmentInterval.seconds, repeats: true) { [weak self] _ in
            self?.saveCursor()
        }
        RunLoop.main.add(timer, forMode: .common)
        cursorSaver = timer
    }

    /// On the main thread, where the pointer is logged; the encoding and writing happen off it.
    private func saveCursor() {
        guard !savingCursor, let writer = queue.sync(execute: { take }), let start = queue.sync(execute: { writer.startTime })
        else { return }
        savingCursor = true
        let snapshot = cursor.snapshot, url = writer.cursorURL
        cursorQueue.async { [weak self] in
            if let data = try? JSONEncoder().encode(snapshot.log(since: start.seconds)) { try? data.write(to: url, options: .atomic) }
            DispatchQueue.main.async { self?.savingCursor = false }
        }
    }

    /// Waits out a save under way, so it can't land on top of the finished take's log.
    func stopSavingCursor() async {
        await MainActor.run {
            cursorSaver?.invalidate()
            cursorSaver = nil
        }
        await withCheckedContinuation { done in cursorQueue.async { done.resume() } }
    }
}
