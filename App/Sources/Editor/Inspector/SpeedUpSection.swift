//
//  SpeedUpSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import SliceCore
import SwiftUI

struct SpeedUpSection: View {
    @ObservedObject var editor: EditorModel
    @AppStorage("quiet.idle") private var idle = true
    @AppStorage("quiet.typing") private var typing = true
    @AppStorage("quiet.idleSpeed") private var idleSpeed = 4.0
    @AppStorage("quiet.typingSpeed") private var typingSpeed = 2.0

    private var settings: QuietMoments.Settings { .saved }

    var body: some View {
        PanelSection("Smart speed") {
            Button { editor.speedUpQuietMoments(settings) } label: { Label("Speed up quiet moments", systemImage: "hare") }
                .buttonStyle(WideButtonStyle())
                .disabled(!editor.hasPointerLog || (!idle && !typing))
                .help(editor.hasPointerLog ? "Finds idle stretches and long typing with no talking, and plays them faster"
                    : "These takes have no pointer recording to analyse")
            if editor.hasAutoSpeeds {
                Button("Back to normal speed") { editor.clearAutoSpeeds() }
                    .buttonStyle(PillButtonStyle(fullWidth: true))
                    .transition(.opacity)
            }
            MoreOptions(id: "smartSpeed") {
                PanelToggle("Idle moments", isOn: $idle)
                    .help("Nothing moving, no clicks, typing or talking")
                if idle {
                    SegmentedControl(selection: $idleSpeed, options: [2.0, 4, 8], title: SpeedRange.label)
                }
                PanelToggle("Typing", isOn: $typing)
                    .help("A few seconds or more of typing without talking")
                if typing {
                    SegmentedControl(selection: $typingSpeed, options: [2.0, 4, 8], title: SpeedRange.label)
                }
            }
            PanelNote("Sped-up parts play without sound. Select a section on the timeline to set its speed by hand.")
        }
        .animation(Theme.swap, value: editor.hasAutoSpeeds)
        .animation(.snappy, value: idle)
        .animation(.snappy, value: typing)
    }
}

extension QuietMoments.Settings {
    /// What the Smart speed options are set to.
    static var saved: Self {
        let d = UserDefaults.standard
        var s = Self()
        s.idle = d.object(forKey: "quiet.idle") as? Bool ?? s.idle
        s.typing = d.object(forKey: "quiet.typing") as? Bool ?? s.typing
        s.idleSpeed = d.object(forKey: "quiet.idleSpeed") as? Double ?? s.idleSpeed
        s.typingSpeed = d.object(forKey: "quiet.typingSpeed") as? Double ?? s.typingSpeed
        return s
    }
}
