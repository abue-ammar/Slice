//
//  Updater+Sparkle.swift
//  Slice
//
//  Created by rit3zh CX on 10/24/26.
//

import AppKit
import Sparkle

// MARK: - User driver

extension Updater: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: checksAutomatically, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        if intent == .none { phase = .checking }
    }

    func showUpdateFound(with item: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        let release = Release(item)
        let wanted = intent
        intent = .none
        updatesLog.info("Found \(release.version, privacy: .public) (\(release.build, privacy: .public)), stage \(state.stage.rawValue), user \(state.userInitiated)")
        if item.isInformationOnlyUpdate {
            reply(.dismiss)
            if state.userInitiated, let page = release.page { NSWorkspace.shared.open(page) }
            phase = .idle
            return
        }
        let downloaded = state.stage != .notDownloaded
        if wanted == .relaunch || (wanted == .download && !downloaded) {
            intent = wanted
            userSession = true
            phase = wanted == .relaunch ? .installing(release) : .downloading(release, received: 0, total: 0)
            reply(.install)
            return
        }
        phase = downloaded ? .ready(release) : .available(release)
        if !state.userInitiated, putOff.contains(release.build) {
            reply(.dismiss)
            return
        }
        self.reply = reply
        cardShown = true
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        updatesLog.info("No update: \(error.localizedDescription, privacy: .public)")
        intent = .none
        let error = error as NSError
        let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber).flatMap { SPUNoUpdateFoundReason(rawValue: $0.int32Value) }
        switch reason {
        case nil, .unknown?, .onLatestVersion?, .onNewerThanLatestVersion?: phase = .upToDate
        default: phase = .failed(error.localizedRecoverySuggestion ?? error.localizedDescription, nil)
        }
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        updatesLog.error("Update failed: \(String(describing: error), privacy: .public)")
        let release = phase.release
        reply = nil
        cancelDownload = nil
        intent = .none
        userSession = false
        phase = .failed(Self.message(for: error), release)
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelDownload = cancellation
        received = 0
        if let release = phase.release { phase = .downloading(release, received: 0, total: 0) }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        guard case let .downloading(release, shown, _) = phase else { return }
        guard Self.hasRoom(for: expectedContentLength) else {
            problem = "There isn't enough free space on this Mac for the update. Free up some space and try again."
            cancelDownload?()
            return
        }
        phase = .downloading(release, received: shown, total: expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        guard case let .downloading(release, shown, total) = phase else { return }
        received += length
        // Sparkle reports every few kilobytes; redraw on each whole percent (or megabyte, with no size to go by).
        let step = total > 0 ? max(total / 100, 1) : 1 << 20
        if received / step != shown / step {
            phase = .downloading(release, received: total > 0 ? min(received, total) : received, total: total)
        }
    }

    func showDownloadDidStartExtractingUpdate() {
        cancelDownload = nil
        if let release = phase.release { phase = .preparing(release) }
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let release = phase.release else { return reply(.dismiss) }
        updatesLog.info("Ready to install \(release.version, privacy: .public)")
        if intent == .relaunch, busyReason == nil {
            intent = .none
            phase = .installing(release)
            reply(.install)
            return
        }
        intent = .none
        self.reply = reply
        phase = .ready(release)
        cardShown = true
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if let release = phase.release { phase = .installing(release) }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        phase = .idle
        cardShown = false
        acknowledgement()
    }

    func showUpdateInFocus() {
        if phase.release != nil { cardShown = true }
    }

    /// Sparkle's done with this round. Replies it gave are no longer good; what's on offer stays on offer.
    func dismissUpdateInstallation() {
        reply = nil
        cancelDownload = nil
        userSession = false
        if let problem {
            self.problem = nil
            phase = .failed(problem, phase.release)
            return
        }
        switch phase {
        case .checking: phase = .idle
        case let .downloading(release, _, _), let .preparing(release): phase = .available(release)
        case let .installing(release): phase = .ready(release)
        default: break
        }
    }
}

// MARK: - Updater delegate

extension Updater: SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }

    // Automatic downloads run without the user driver; these keep Settings showing where they are.
    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        guard !userSession else { return }
        phase = .downloading(Release(item), received: 0, total: 0)
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        guard !userSession else { return }
        phase = .preparing(Release(item))
    }

    /// A background download or check that fails says nothing; the next scheduled check tries again.
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        updatesLog.info("Update cycle stopped: \(error.localizedDescription, privacy: .public)")
        guard !userSession else { return }
        switch phase {
        case .downloading, .preparing: phase = .idle
        default: break
        }
    }

    /// An automatic download is unpacked and waiting. Sparkle installs it when Slice quits; until then the card offers
    /// to install it now.
    func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                 immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let release = Release(item)
        updatesLog.info("Downloaded \(release.version, privacy: .public) in the background; installs on quit")
        installNow = immediateInstallHandler
        phase = .ready(release)
        if !putOff.contains(release.build) { cardShown = true }
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        lastChecked = updater.lastUpdateCheckDate
    }
}

// MARK: - Helpers

extension Updater {
    /// Room for the archive, the unpacked app and the copy that replaces this one, with some to spare.
    static func hasRoom(for bytes: UInt64) -> Bool {
        let values = try? URL.cachesDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let free = values?.volumeAvailableCapacityForImportantUsage, bytes > 0 else { return true }
        return free > Int64(clamping: bytes) * 5
    }

    static func message(for error: any Error) -> String {
        let error = error as NSError
        let chain = Array(sequence(first: error) { $0.userInfo[NSUnderlyingErrorKey] as? NSError })
        if chain.contains(where: { ($0.domain == NSPOSIXErrorDomain && $0.code == Int(ENOSPC))
            || ($0.domain == NSCocoaErrorDomain && $0.code == NSFileWriteOutOfSpaceError) }) {
            return "There isn't enough free space on this Mac for the update. Free up some space and try again."
        }
        if chain.contains(where: { $0.domain == NSURLErrorDomain }) {
            return "Couldn't reach GitHub. Check your connection and try again."
        }
        // Sparkle wraps the cause (a bad signature inside an installation error, say), so look through the whole chain.
        let codes = chain.filter { $0.domain == SUSparkleErrorDomain }.map { OSStatus(clamping: $0.code) }
        func has(_ errors: SUError...) -> Bool { errors.contains { codes.contains($0.rawValue) } }
        if has(.signatureError, .validationError) {
            return "The update didn't pass its signature check, so it wasn't installed."
        }
        if has(.runningFromDiskImageError, .installationWriteNoPermissionError) {
            return "Slice can't update itself where it is. Move it to your Applications folder and try again."
        }
        if has(.appcastParseError, .appcastError) { return "Couldn't read the latest release on GitHub. Try again later." }
        if has(.downloadError) { return "The download didn't finish. Try again." }
        if has(.unarchivingError) { return "The update couldn't be unpacked. Try again." }
        return error.localizedDescription
    }
}
