//
//  EditorModel+Cutting.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import SliceCore
import SwiftUI

struct CutFlash: Equatable {
    let id = UUID()
    let time: Double
}

extension EditorModel {
    func toggleCutting() {
        isCutting.toggle()
    }

    func splitAtPlayhead() {
        split(at: time)
    }

    func split(at t: Double) {
        var p = project
        guard p.split(at: t) else { return }
        // Each cut is its own undo step, even when several land in quick succession.
        lastChangeAt = .distantPast
        project = p
        lastChangeAt = .distantPast
        let flash = CutFlash(time: t)
        cutFlash = flash
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            if self?.cutFlash == flash { self?.cutFlash = nil }
        }
    }
}
