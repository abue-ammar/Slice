//
//  SmartZoomSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/11/26.
//

import SliceCore
import SwiftUI

struct SmartZoomSection: View {
    @ObservedObject var editor: EditorModel
    @AppStorage(EditorModel.autoZoomOnStopKey) private var onStop = true

    var body: some View {
        let s = editor.project.autoZoom
        let d = AutoZoomSettings()
        PanelSection("Smart zoom") {
            PanelToggle("Zoom new recordings automatically", isOn: $onStop)
                .help("When you stop recording, finds the clicks, typing and pauses worth a closer look and zooms on them")
            PanelSlider("Intensity", value: $editor.project.autoZoom.intensity, in: 0 ... 1, default: d.intensity) { v in
                let scale = String(format: "%.1f×", AutoZoomSettings.scale(intensity: v))
                return v < 0.34 ? "Subtle · \(scale)" : v < 0.67 ? "Medium · \(scale)" : "Strong · \(scale)"
            }
            .help("How far zooms go in. Each zoom still widens to keep what it frames in view.")
            PanelSlider("Zoom on", value: $editor.project.autoZoom.selectivity, in: 0 ... 1, default: d.selectivity) { v in
                v < 0.34 ? "More moments" : v < 0.67 ? "Balanced" : "Key moments only"
            }
            .help("How choosy it is about which moments deserve a zoom")
            if let p = editor.smartZoomProgress {
                SmartZoomProgress(progress: p) { editor.cancelSmartZoom() }
                    .transition(.opacity)
            } else {
                Button { editor.runSmartZoom() } label: { Label("Find zoom moments", systemImage: "sparkle.magnifyingglass") }
                    .buttonStyle(WideButtonStyle())
                    .disabled(!editor.hasPointerLog)
                    .help(editor.hasPointerLog ? "Analyse the whole recording again. Zooms you've edited are kept."
                        : "These takes have no pointer recording to analyse")
                    .transition(.opacity)
            }
            PanelNote("Finds clicks, typing and pauses and zooms on them. They're marked Auto on the timeline; edit or delete them like any zoom.")
        }
        .animation(Theme.swap, value: editor.smartZoomProgress == nil)
        .animation(Theme.swap, value: s)
    }
}

extension AutoZoomSettings {
    static func scale(intensity: Double) -> Double {
        var s = AutoZoomSettings()
        s.intensity = intensity
        return s.targetScale
    }
}

struct SmartZoomProgress: View {
    let progress: Double
    let cancel: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle.magnifyingglass").foregroundStyle(Theme.zoom)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Finding zoom moments").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.rounded(11).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: progress))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule().fill(Theme.zoom).frame(width: max(geo.size.width * progress, 4))
                    }
                }
                .frame(height: 4)
                .animation(.smooth(duration: 0.3), value: progress)
            }
            Button(action: cancel) { Image(systemName: "xmark") }
                .buttonStyle(IconButtonStyle(size: 22, iconSize: 10))
                .help("Stop")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.control))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct SmartZoomStatus: View {
    @ObservedObject var editor: EditorModel

    var body: some View {
        Group {
            if let p = editor.smartZoomProgress {
                HStack(spacing: 7) {
                    ProgressView(value: p).progressViewStyle(.circular).controlSize(.mini)
                    Text("Finding zoom moments… \(Int((p * 100).rounded()))%")
                        .font(.system(size: 12).monospacedDigit())
                        .contentTransition(.numericText(value: p))
                    Button { editor.cancelSmartZoom() } label: { Image(systemName: "xmark") }
                        .buttonStyle(IconButtonStyle(size: 18, iconSize: 9))
                        .help("Stop")
                }
            } else if let note = editor.smartZoomNote {
                Label(note, systemImage: editor.noteSymbol).font(.system(size: 12))
            }
        }
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Theme.control))
        .transition(.opacity.combined(with: .offset(y: 4)))
    }
}
