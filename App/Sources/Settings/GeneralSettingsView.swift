//
//  GeneralSettingsView.swift
//  Slice
//
//  Created by rit3zh CX on 10/20/26.
//

import SwiftUI

struct GeneralSettingsView: View {
    var body: some View {
        Form {
            UpdateSettingsSection()

            Section {
                LabeledContent("Draw on screen") { ShortcutRecorder() }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Works from any app, before or while recording. Click the shortcut, then press the keys you want; it needs ⌘, ⌥ or ⌃.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Shows a shortcut; click it and press new keys to change it, Esc to keep the old one.
struct ShortcutRecorder: View {
    @State private var keys = AnnotationController.toggleKeys
    @State private var listening = false
    @State private var monitor: Any?
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                Button { listening ? stop() : listen() } label: {
                    HStack(spacing: 3) {
                        if listening {
                            Text("Press keys…").foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(keys.enumerated()), id: \.offset) { _, k in KeyCap(key: k) }
                        }
                    }
                    .frame(minWidth: 96, minHeight: 24)
                    .padding(.horizontal, 6)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(listening ? Theme.accent : Color.white.opacity(0.12), lineWidth: listening ? 1.5 : 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click, then press the new shortcut")
                if AnnotationController.shared.shortcut != .standard, !listening {
                    Button("Reset") { apply(.standard) }
                        .controlSize(.small)
                        .help("Back to \(DrawShortcut.standard.keys.joined())")
                }
            }
            if let problem {
                Text(problem).font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .animation(Theme.hover, value: listening)
        .onDisappear(perform: stop)
    }

    private func listen() {
        problem = nil
        listening = true
        AnnotationController.shared.suspendShortcut()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
            } else if let next = DrawShortcut(event: event) {
                apply(next)
            } else {
                problem = "Add ⌘, ⌥ or ⌃ so typing doesn't set it off."
            }
            return nil
        }
    }

    private func apply(_ next: DrawShortcut) {
        if !AnnotationController.shared.setShortcut(next) {
            problem = "\(next.keys.joined()) is taken by another app. Try another."
        } else {
            problem = nil
        }
        keys = AnnotationController.toggleKeys
        end()
    }

    private func stop() {
        guard listening else { return }
        end()
        AnnotationController.shared.install()
    }

    private func end() {
        listening = false
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
    }
}
