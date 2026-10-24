//
//  CameraOverdubSheet.swift
//  Slice
//
//  Created by rit3zh CX on 10/24/26.
//

import AVFoundation
import SliceCore
import SwiftUI

struct CameraOverdubSheet: View {
    @ObservedObject var overdub: CameraOverdub
    @ObservedObject private var devices = CaptureDevices.shared
    @AppStorage("setup.camera") private var cameraID = ""
    @AppStorage("setup.mic") private var micID = ""
    @AppStorage("setup.micChosen") private var micChosen = false
    @AppStorage("overdub.playSound") private var playSound = true

    private var idle: Bool { overdub.phase == .ready }
    /// The camera to film with: the saved one, or the first there is when that's off or unplugged.
    private var camera: AVCaptureDevice? { devices.cameras.first { $0.uniqueID == cameraID } ?? devices.cameras.first }
    private var mic: AVCaptureDevice? { devices.mics.first { $0.uniqueID == micID } }
    private var aspect: CGFloat {
        let s = overdub.clip.screenPixelSize
        return s.width > 0 && s.height > 0 ? s.width / s.height : 16 / 9
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Record camera over take \(overdub.index + 1)").font(.rounded(17, .semibold))
                Text("The take plays while your camera films. Stop whenever you like; past that the take has no camera.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            stage
            progress
            controls
            if let problem = overdub.problem {
                Text(problem).font(.system(size: 12)).foregroundStyle(.orange)
            } else if mic != nil && playSound && idle {
                Text("Use headphones, so the mic doesn't pick up the take's sound.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        .frame(width: 620)
        .background(Theme.window)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .animation(Theme.swap, value: overdub.phase)
        .animation(Theme.swap, value: overdub.problem)
        .onAppear { devices.refresh() }
        .onChange(of: camera?.uniqueID, initial: true) { useDevices() }
        .onChange(of: mic?.uniqueID) { useDevices() }
        .onChange(of: playSound, initial: true) { overdub.player.isMuted = !playSound }
        .onExitCommand { overdub.cancel() }
        .onDisappear { overdub.cancel() }
        .interactiveDismissDisabled()
    }

    private func useDevices() { overdub.use(cameraID: camera?.uniqueID, micID: mic?.uniqueID) }

    private var stage: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return ZStack {
            Color.black
            PlayerLayerView(player: overdub.player)
            if case let .countdown(n) = overdub.phase {
                Text("\(n)")
                    .font(.system(size: 64, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 12)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.smooth(duration: 0.3), value: n)
                    .transition(.opacity)
            }
        }
        .aspectRatio(aspect, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: 330)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.stroke))
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                Circle().fill(Color.white.opacity(0.06))
                if let session = overdub.session {
                    CameraPreview(session: session).clipShape(Circle()).transition(.opacity)
                } else {
                    Image(systemName: "video.slash").font(.system(size: 18)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 104, height: 104)
            .overlay(Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
            .padding(12)
            .animation(Theme.swap, value: overdub.session != nil)
        }
        .frame(maxWidth: .infinity)
    }

    private var progress: some View {
        let total = max(overdub.clip.duration, 0.01)
        return HStack(spacing: 10) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule().fill(Color.white.opacity(0.18)).frame(width: geo.size.width * overdub.from / total)
                    Capsule()
                        .fill(overdub.phase == .recording ? Color(red: 0.96, green: 0.3, blue: 0.29) : Theme.accent)
                        .frame(width: geo.size.width * overdub.position / total)
                }
            }
            .frame(height: 4)
            Text("\(format(overdub.position)) / \(format(overdub.clip.duration))")
                .font(.rounded(12).monospacedDigit())
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(devices.cameras, id: \.uniqueID) { c in
                    Toggle(c.localizedName, isOn: Binding(get: { camera?.uniqueID == c.uniqueID }, set: { if $0 { cameraID = c.uniqueID } }))
                }
            } label: {
                Label(camera?.localizedName ?? "No camera", systemImage: "video.fill").lineLimit(1)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(PillButtonStyle())
            .fixedSize()
            .disabled(!idle)
            Menu {
                Toggle("No microphone", isOn: Binding(get: { mic == nil }, set: { if $0 { micID = ""; micChosen = true } }))
                ForEach(devices.mics, id: \.uniqueID) { m in
                    Toggle(m.localizedName, isOn: Binding(get: { mic?.uniqueID == m.uniqueID },
                                                          set: { if $0 { micID = m.uniqueID; micChosen = true } }))
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: mic == nil ? "mic.slash" : "mic.fill")
                    Text(mic?.localizedName ?? "No microphone").lineLimit(1)
                    if mic != nil { LevelBars(level: overdub.micLevel) }
                }
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(PillButtonStyle())
            .fixedSize()
            .help(overdub.clip.micFile == nil ? "Record your voice too" : "Recording a mic replaces the take's own")
            .disabled(!idle)
            Button { playSound.toggle() } label: {
                Image(systemName: playSound ? "speaker.wave.2.fill" : "speaker.slash.fill")
            }
            .buttonStyle(IconButtonStyle(selected: playSound))
            .help(playSound ? "The take plays with its sound" : "The take plays silently")
            Spacer(minLength: 8)
            Button("Cancel") { overdub.cancel() }
                .buttonStyle(PillButtonStyle())
                .disabled(overdub.phase == .saving)
            Button { overdub.phase == .recording ? overdub.stop() : overdub.record() } label: {
                HStack(spacing: 7) {
                    if overdub.phase == .recording {
                        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(.white).frame(width: 8, height: 8)
                    } else {
                        Circle().fill(.white).frame(width: 8, height: 8)
                    }
                    Text(recordTitle).contentTransition(.interpolate)
                }
            }
            .buttonStyle(PillButtonStyle(prominent: true))
            .disabled(!(idle && overdub.session != nil) && overdub.phase != .recording)
        }
    }

    private var recordTitle: String {
        switch overdub.phase {
        case .ready: "Record"
        case .countdown: "Starting…"
        case .recording: "Stop"
        case .saving: "Saving…"
        }
    }
}

private struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
