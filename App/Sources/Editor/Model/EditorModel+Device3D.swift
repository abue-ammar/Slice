//
//  EditorModel+Device3D.swift
//  Slice
//
//  Created by rit3zh CX on 10/15/26.
//

import Foundation
import SliceCore

extension EditorModel {
    /// Takes just recorded with "Edit on a 3D iPhone" open on the 3D phone, with its tab showing.
    func open3DAfterRecording(clipIDs: Set<UUID>) {
        guard project.clips.contains(where: { clipIDs.contains($0.id) && $0.device?.opensIn3D == true }) else { return }
        if !project.device3D.enabled { project.device3D.enabled = true }
        UserDefaults.standard.set(InspectorTab.device3D.rawValue, forKey: "sidePanel.tab")
        selection = nil
    }

    /// With the 3D tab open and nothing selected, or a keyframe selected, the preview takes hold of the phone
    /// (`Device3DPoseOverlay`).
    func handlesPhoneInPreview(tab: String) -> Bool {
        guard shows3DTrack else { return false }
        if case .keyframe = selection { return true }
        return tab == InspectorTab.device3D.rawValue && selection == nil
    }

    /// The timeline's 3D track, for projects showing takes on a 3D device.
    var shows3DTrack: Bool { project.shows3D }

    /// The kinds of device this project's takes can be shown on: phones for iPhone takes, Macs for screen recordings.
    var available3DKinds: [Device3DKind] { Device3DKind.allCases.filter { project.hasTakes(for: $0) } }

    /// Turns the 3D device on or off. On, it's a model for the takes there are: a Mac for a project of screen
    /// recordings, even if an iPhone was last chosen.
    func enable3D(_ on: Bool) {
        if on, !project.hasTakes(for: project.device3D.model.kind), let kind = available3DKinds.first {
            select3DModel(Device3DModel.models(kind)[0])
        }
        project.device3D.enabled = on
    }

    /// Chooses a model, in its own finish if the last one doesn't come in it; moving between a phone and a laptop it
    /// starts from the new kind's natural pose.
    func select3DModel(_ model: Device3DModel) {
        var settings = project.device3D
        if settings.model.kind != model.kind { settings.placement = model.defaultPlacement }
        settings.model = model
        if !model.finishes.contains(settings.finish) { settings.finish = model.finishes[0] }
        project.device3D = settings
    }

    // MARK: - Keyframes

    var selectedKeyframe: Device3DKeyframe? {
        guard case let .keyframe(id) = selection else { return nil }
        return project.device3D.keyframes.first { $0.id == id }
    }

    /// The selected keyframe while the playhead is on it. Scrub away and posing keys the phone where the playhead is.
    private var keyframeAtPlayhead: Device3DKeyframe? {
        selectedKeyframe.flatMap { abs($0.time - time) <= 1.0 / 30 ? $0 : nil }
    }

    /// The pose being edited: the selected keyframe's, or the phone's at the playhead.
    var editedPlacement: Device3DPlacement {
        keyframeAtPlayhead?.placement ?? project.device3D.placement(at: time)
    }

    /// Poses the phone: the selected keyframe, else the keyframe at the playhead (made there when the phone is
    /// keyframed), else the pose controls. A keyframe made here is selected.
    func setPlacement(_ placement: Device3DPlacement) {
        var settings = project.device3D
        let key = settings.setPlacement(placement, at: time, keyframe: keyframeAtPlayhead?.id)
        guard settings != project.device3D else { return }
        project.device3D = settings
        if let key, selection != .keyframe(key) { selection = .keyframe(key) }
    }

    func updatePlacement(_ change: (inout Device3DPlacement) -> Void) {
        var p = editedPlacement
        change(&p)
        setPlacement(p)
    }

    /// A keyframe at `t` holding the pose the phone has there, selected; the playhead goes to it.
    func addKeyframe(at t: Double) {
        let t = min(max(t, 0), duration)
        if let existing = project.device3D.keyframe(at: t) {
            selectKeyframe(existing.id)
            return
        }
        let key = Device3DKeyframe(time: t, placement: project.device3D.placement(at: t))
        project.device3D.keyframes.append(key)
        project.device3D.keyframes.sort { $0.time < $1.time }
        selectKeyframe(key.id)
    }

    func selectKeyframe(_ id: UUID) {
        selection = .keyframe(id)
        if let key = project.device3D.keyframes.first(where: { $0.id == id }) { seek(to: key.time) }
    }

    func moveKeyframe(_ id: UUID, to t: Double) {
        guard let i = project.device3D.keyframes.firstIndex(where: { $0.id == id }) else { return }
        project.device3D.keyframes[i].time = min(max(t, 0), duration)
        project.device3D.keyframes.sort { $0.time < $1.time }
    }

    func updateKeyframe(_ id: UUID, _ change: (inout Device3DKeyframe) -> Void) {
        guard let i = project.device3D.keyframes.firstIndex(where: { $0.id == id }) else { return }
        change(&project.device3D.keyframes[i])
    }

    /// Seconds a lid takes to open or close.
    static let lidMove = 1.2

    /// Keys the lid opening (or closing) from the playhead, the rest of the pose as it is: from shut to as far open as
    /// it stands there (upright, if it's shut already), or back.
    func animateLid(open: Bool) {
        var s = project.device3D
        let t0 = min(max(time, 0), duration), t1 = min(t0 + Self.lidMove, duration)
        guard t1 - t0 > 0.1 else { return }
        let now = editedPlacement.lid
        let wide = now > 5 ? now : Device3DPlacement.openLid
        let (from, to) = open ? (0.0, wide) : (wide, 0.0)
        // Keyframes already inside the move go along with it.
        let ease = EasingCurve.smooth
        for i in s.keyframes.indices where s.keyframes[i].time > t0 && s.keyframes[i].time < t1 {
            s.keyframes[i].placement.lid = from + (to - from) * ease((s.keyframes[i].time - t0) / (t1 - t0))
        }
        for (t, lid) in [(t0, from), (t1, to)] {
            var p = s.placement(at: t)
            p.lid = lid
            if let key = s.keyframe(at: t), let i = s.keyframes.firstIndex(where: { $0.id == key.id }) {
                s.keyframes[i].placement = p
            } else {
                s.keyframes.append(Device3DKeyframe(time: t, placement: p))
                s.keyframes.sort { $0.time < $1.time }
            }
        }
        project.device3D = s
    }

    func removeAllKeyframes() {
        if case .keyframe = selection { selection = nil }
        project.device3D.keyframes = []
    }

    /// Loads the 3D model (and draws a frame off screen) ahead of the first 3D frame.
    func warmUp3D() {
        guard project.hasTakes(for: project.device3D.model.kind) else { return }
        let model = project.device3D.model
        Task.detached(priority: .utility) {
            let status = Device3DRenderer.shared.status(for: model)
            if case .ready = status { Device3DRenderer.shared.warmUp(model) }
            await MainActor.run { self.device3DStatus = status }
        }
    }

    /// Device takes recorded before the display's place in the picture was saved with them get it from their frame,
    /// so the 3D phone can lift the screen out of the frame.
    static func withDeviceOpenings(_ project: Project, catalog: DeviceFrameCatalog) -> Project {
        var project = project
        for i in project.clips.indices {
            guard var device = project.clips[i].device, device.screen == nil else { continue }
            let canvas = project.clips[i].screenPixelSize
            guard canvas.width > 0, canvas.height > 0 else { continue }
            let landscape = canvas.width > canvas.height
            if let model = device.frame {
                guard let definition = try? catalog.definition(model: model, color: DeviceColor(device.color ?? ""))
                    ?? catalog.colors(for: model).first.flatMap({ try? catalog.definition(model: model, color: $0) }) else { continue }
                let layout = DeviceLayout(frame: definition, streamSize: landscape ? CGSize(width: 2, height: 1) : CGSize(width: 1, height: 2))
                // Only when the take really is this frame's picture.
                guard abs(layout.canvas.width / layout.canvas.height - canvas.width / canvas.height) < 0.01 else { continue }
                device.screen = layout.screenRect
                device.cutout = layout.cutoutRect
            } else {
                device.screen = CGRect(x: 0, y: 0, width: 1, height: 1)
            }
            project.clips[i].device = device
        }
        return project
    }
}
