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

    /// The timeline's 3D track, for projects showing an iPhone take on the 3D phone.
    var shows3DTrack: Bool { project.device3D.enabled && project.hasDeviceRecording }

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

    func removeAllKeyframes() {
        if case .keyframe = selection { selection = nil }
        project.device3D.keyframes = []
    }

    /// Loads the 3D model (and draws a frame off screen) ahead of the first 3D frame.
    func warmUp3D() {
        guard project.hasDeviceRecording else { return }
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
