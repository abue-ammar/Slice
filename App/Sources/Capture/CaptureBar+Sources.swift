//
//  CaptureBar+Sources.swift
//  Slice
//
//  Created by rit3zh CX on 10/1/26.
//

import SwiftUI

extension CaptureBar {
    func choose(_ k: Kind) {
        let spring = Animation.spring(response: 0.38, dampingFraction: 0.8)
        switch k {
        case .display:
            withAnimation(spring) { kind = .display }
            if displays.count > 1 { picker = .source(.display) }
        case .window:
            if kind == .window { picker = .source(.window) }
            withAnimation(spring) { kind = .window }
            Task { await loadWindows() }
        case .area:
            if areaOverlay.area == nil {
                Task { await drawArea() }
            } else {
                withAnimation(spring) { kind = .area }
                picker = .source(.area)
            }
        case .device:
            withAnimation(spring) { kind = .device }
            picker = .source(.device)
        }
    }

    func hasChoices(_ k: Kind) -> Bool {
        switch k {
        case .display: displays.count > 1
        case .window, .device: true
        case .area: areaOverlay.area != nil
        }
    }

    func help(for k: Kind) -> String {
        switch k {
        case .display: displays.count > 1 ? displays.first { $0.id == displayID }.map { "Recording \($0.name)" } ?? "Record a whole display"
            : "Record a whole display"
        case .window: windowID.flatMap { id in windows.first { $0.windowID == id } }.map { "Recording \($0.title ?? "a window")" }
            ?? "Record one window"
        case .area:
            if case let .area(_, r) = areaOverlay.area { "Recording a \(Int(r.width)) × \(Int(r.height)) area. Click to change it" }
            else { "Record part of the screen" }
        case .device: deviceManager.devices.isEmpty ? "Connect an iPhone with a USB cable" : "Record a connected iPhone in its frame"
        }
    }

    @ViewBuilder func sourcePicker(_ k: Kind) -> some View {
        switch k {
        case .display:
            PickerList(title: "Display") {
                ForEach(displays) { display in
                    PickerRow(title: display.name, subtitle: display.detail, selected: displayID == display.id,
                              symbol: display.isBuiltIn ? "laptopcomputer" : "display") {
                        displayID = display.id
                        savedDisplay = Int(display.id)
                        picker = nil
                    }
                }
            }
        case .window:
            PickerList(title: "Window", scrolls: windows.count > 7) {
                if let loadError {
                    Text(loadError).font(.system(size: 11)).foregroundStyle(.orange).padding(8)
                } else if windows.isEmpty {
                    Text("No windows to record").font(.system(size: 12)).foregroundStyle(.secondary).padding(8)
                }
                ForEach(windows, id: \.windowID) { w in
                    let app = w.owningApplication
                    PickerRow(title: app?.applicationName ?? "Unknown", subtitle: w.title.flatMap { $0.isEmpty ? nil : $0 },
                              selected: windowID == w.windowID,
                              icon: app.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.icon },
                              onHover: { windowPicker.preview(w.windowID, $0) }) {
                        windowID = w.windowID
                        picker = nil
                    }
                }
            }
        case .device:
            DevicePanel(deviceID: $deviceID)
        case .area:
            AreaPanel(overlay: areaOverlay) {
                picker = nil
                Task { await drawArea() }
            }
        }
    }

    func drawArea() async {
        picker = nil
        guard await areaOverlay.draw() else { return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.8)) { kind = .area }
    }

    var areaMode: AreaOverlay.Mode {
        guard kind == .area, areaOverlay.area != nil else { return .hidden }
        return switch stage {
        case .setup: .editing
        case .countdown, .live, .drawing: .recording
        case .saving: .hidden
        }
    }

    func refreshDisplays() {
        displays = DisplayInfo.all()
        let ids = Set(displays.map(\.id))
        if displayID.map({ !ids.contains($0) }) ?? true {
            let saved = CGDirectDisplayID(truncatingIfNeeded: savedDisplay)
            let current = NSScreen.main?.displayID
            displayID = ids.contains(saved) ? saved
                : current.flatMap { ids.contains($0) ? $0 : nil } ?? (displays.first { $0.isBuiltIn } ?? displays.first)?.id
        }
        if areaOverlay.local != nil, !(areaOverlay.displayID.map(ids.contains) ?? false) {
            areaOverlay.clear()
            if kind == .area { kind = .display }
        }
        if case .source(.display) = picker, displays.count < 2 { picker = nil }
    }

    var source: CaptureSource? {
        switch kind {
        case .display: displayID.map { .display($0) }
        case .window: windowID.map { .window($0) }
        case .area: areaOverlay.area
        case .device: deviceID.map { .device($0) }
        }
    }

    var recordEnabled: Bool {
        selectedDevice.map { $0.info.state == .streaming } ?? true
    }

    var recordTitle: String {
        if let device = selectedDevice, device.info.state != .streaming { return device.info.state.title }
        guard source != nil else {
            return switch kind {
            case .window: "Pick a Window"
            case .area: "Select an Area"
            default: "Pick a Source"
            }
        }
        return model.setupAppendTo == nil ? "Record" : "Record Take"
    }
}
