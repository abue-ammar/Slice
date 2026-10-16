//
//  EditorCommand.swift
//  Slice
//
//  Created by rit3zh CX on 10/2/26.
//

import AppKit
import SwiftUI

enum PaletteGroup: String, CaseIterable, Identifiable {
    case playback, edit, timeline, panels, view, project

    var id: Self { self }

    var title: String {
        switch self {
        case .playback: "Playback"
        case .edit: "Edit"
        case .timeline: "Timeline"
        case .panels: "Panels"
        case .view: "View"
        case .project: "Project"
        }
    }
}

struct EditorCommand: Identifiable {
    let id: String
    let title: String
    var detail: String?
    let symbol: String
    let group: PaletteGroup
    var keys: [String] = []
    var keywords = ""
    var enabled = true
    let run: () -> Void

    func score(_ query: String) -> Int {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return 1 }
        let t = title.lowercased()
        if t.hasPrefix(q) { return 100 }
        if t.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 80 }
        if t.contains(q) { return 60 }
        let hay = "\(t) \(keywords.lowercased()) \(group.title.lowercased()) \((detail ?? "").lowercased())"
        if q.split(separator: " ").allSatisfy({ hay.contains($0) }) { return 40 }
        var i = t.startIndex
        for ch in q where ch != " " {
            guard let f = t[i...].firstIndex(of: ch) else { return 0 }
            i = t.index(after: f)
        }
        return 10
    }
}
