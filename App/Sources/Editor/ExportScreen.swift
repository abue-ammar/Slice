//
//  ExportScreen.swift
//  Slice
//
//  Created by rit3zh CX on 10/6/26.
//

import AppKit
import SliceCore
import SwiftUI

struct ExportLayer: View {
    let job: ExportJob?
    let stop: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            if let job {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Theme.window.opacity(0.78)
                }
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
                .transition(.opacity)
                ExportPanel(job: job, stop: stop, close: close)
                    .geometryGroup()
                    .transition(.exportPanel)
            }
        }
        .animation(.smooth(duration: 0.4), value: job == nil)
    }
}

private struct ExportPanel: View {
    let job: ExportJob
    let stop: () -> Void
    let close: () -> Void
    @State private var showInfo = false

    private var percent: Int { Int((job.progress * 100).rounded(.down)) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(heading)
                    .contentTransition(.interpolate)
                if job.isRunning {
                    HStack(spacing: 10) {
                        Text("•")
                        Text("\(percent)%")
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(percent)))
                    }
                    .transition(.blurReplace)
                }
                Button { showInfo.toggle() } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17, weight: .regular))
                        .foregroundStyle(.secondary)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Export details")
                .popover(isPresented: $showInfo, arrowEdge: .bottom) { ExportDetails(job: job) }
            }
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(.primary)

            ExportProgressBar(progress: job.progress, preparing: job.phase == .preparing, failed: isFailed)
                .frame(width: 300, height: 4)
                .padding(.top, 22)

            status
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
                .padding(.top, 14)

            actions
                .padding(.top, 52)
        }
        .animation(.smooth(duration: 0.35), value: job)
    }

    private var isFailed: Bool {
        if case .failed = job.phase { true } else { false }
    }

    private var heading: String {
        switch job.phase {
        case .preparing, .rendering, .finishing: "Exporting video"
        case .done: "Video exported"
        case .failed: "Export failed"
        }
    }

    private var status: some View {
        Group {
            switch job.phase {
            case .preparing: Text(job.note ?? "Preparing export…").contentTransition(.numericText())
            case .rendering:
                if let left = job.remaining {
                    Text(timeLeft(left)).contentTransition(.numericText(countsDown: true))
                } else {
                    Text("Rendering frames…")
                }
            case .finishing: Text("Finishing up…")
            case let .done(bytes):
                Text([job.url.lastPathComponent, bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }]
                    .compactMap { $0 }.joined(separator: " · "))
            case let .failed(message): Text(message)
            }
        }
        .id(statusKind)
        .transition(.blurReplace)
    }

    private var statusKind: Int {
        switch job.phase {
        case .preparing: 0
        case .rendering: job.remaining == nil ? 1 : 2
        case .finishing: 3
        case .done: 4
        case .failed: 5
        }
    }

    private func timeLeft(_ s: Double) -> String {
        switch s {
        case ..<10: "A few seconds left"
        case ..<60: "About \(Int((s / 5).rounded()) * 5) sec left"
        default: "About \(Int((s / 60).rounded(.up))) min left"
        }
    }

    @ViewBuilder private var actions: some View {
        Group {
            switch job.phase {
            case .preparing, .rendering, .finishing:
                Button("Stop export", action: stop)
                    .buttonStyle(ExportButtonStyle())
            case .done:
                HStack(spacing: 10) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([job.url]) }
                        .buttonStyle(ExportButtonStyle())
                    Button("Done", action: close)
                        .buttonStyle(ExportButtonStyle(prominent: true))
                        .keyboardShortcut(.defaultAction)
                }
            case .failed:
                Button("Close", action: close)
                    .buttonStyle(ExportButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .id(job.isRunning)
        .transition(.blurReplace)
    }
}

private struct ExportProgressBar: View {
    let progress: Double
    let preparing: Bool
    let failed: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.1))
                Capsule()
                    .fill(failed ? Color.red.opacity(0.7) : Color.white.opacity(0.9))
                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                if preparing {
                    SwiftUI.TimelineView(.animation) { context in
                        let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
                        let w = geo.size.width * 0.35
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: w)
                            .offset(x: -w + (geo.size.width + w) * t)
                    }
                    .clipShape(Capsule())
                    .transition(.opacity)
                }
            }
        }
        .animation(.smooth(duration: 0.5), value: progress)
        .animation(.smooth(duration: 0.3), value: preparing)
    }
}

private struct ExportDetails: View {
    let job: ExportJob

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
            row("Resolution", "\(Int(job.size.width)) × \(Int(job.size.height))")
            row("Frame rate", "\(job.fps) fps")
            row("Codec", "\(job.hevc ? "HEVC" : "H.264") · \(Int((Double(job.bitRate) / 1_000_000).rounded())) Mbit/s")
            row("Length", format(job.duration))
            row("Saving to", job.url.deletingLastPathComponent().lastPathComponent + "/" + job.url.lastPathComponent)
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(maxWidth: 320)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).monospacedDigit().lineLimit(1).truncationMode(.middle)
        }
    }
}

private struct ExportButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        ExportButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct ExportButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let prominent: Bool
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(prominent ? Color.black : Color.primary)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(prominent ? Color.white.opacity(hovering ? 1 : 0.9) : hovering ? Theme.controlHover : Theme.control))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .onHover { hovering = $0 }
            .animation(Theme.hover, value: hovering)
            .animation(Theme.press, value: configuration.isPressed)
    }
}

private struct ExportPanelFocus: ViewModifier {
    let t: CGFloat

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.03 * t)
            .offset(y: 8 * t)
            .blur(radius: 6 * t)
            .opacity(1 - t)
    }
}

private extension AnyTransition {
    static var exportPanel: AnyTransition {
        .modifier(active: ExportPanelFocus(t: 1), identity: ExportPanelFocus(t: 0))
    }
}
