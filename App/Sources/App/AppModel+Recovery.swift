//
//  AppModel+Recovery.swift
//  Slice
//
//  Created by rit3zh CX on 10/17/26.
//

import AppKit
import SliceCore

extension AppModel {
    /// At launch: puts back any take cut off when Slice last stopped mid-recording, then offers to open its project.
    func recoverInterruptedTakes() async {
        let found = await ProjectBundle.recoverInterruptedTakes(adding: NSDocumentController.shared.recentDocumentURLs)
        recovery = nil
        guard let first = found.first else { return }
        reloadProjects()
        recovered = first
        showRecovered()
    }

    /// The projects window, where the alert about it shows. Until SwiftUI hands over `openWindow` there's no window to
    /// open, and this runs again once it does.
    func showRecovered() {
        guard openWindow != nil else { return }
        Self.prewarming = false
        presentMainWindow(from: nil)
    }

    /// Opening a project waits for the launch's recovery, which may be adding a take to that very project: an editor
    /// opened first would save its copy over it. True when `then` was put off until recovery is done.
    func waitForRecovery(_ then: @escaping () -> Void) -> Bool {
        guard let recovery else { return false }
        Task {
            await recovery.value
            then()
        }
        return true
    }
}
