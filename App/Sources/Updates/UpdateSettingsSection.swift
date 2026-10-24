//
//  UpdateSettingsSection.swift
//  Slice
//
//  Created by rit3zh CX on 10/24/26.
//

import SwiftUI

struct UpdateSettingsSection: View {
    @ObservedObject private var updater = Updater.shared

    var body: some View {
        Section {
            Toggle("Automatically check for updates", isOn: $updater.checksAutomatically)
            Toggle("Automatically download updates", isOn: $updater.downloadsAutomatically)
                .disabled(!updater.checksAutomatically)
            status
            progress
        } header: {
            Text("General")
        } footer: {
            Text("Updates come from Slice's releases on GitHub, and each one's signature is checked before it installs. A downloaded update installs when you quit Slice, if you haven't installed it already.")
                .foregroundStyle(.secondary)
        }
        .animation(.smooth(duration: 0.25), value: updater.phase)
    }

    private var status: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                detail.font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            button
        }
    }

    private var title: String {
        switch updater.phase {
        case let .available(release): "Slice \(release.version) is available"
        case let .downloading(release, _, _): "Downloading Slice \(release.version)…"
        case let .preparing(release): "Preparing Slice \(release.version)…"
        case let .ready(release): "Slice \(release.version) is ready to install"
        case let .installing(release): "Installing Slice \(release.version)…"
        case .idle, .checking, .upToDate, .failed: "Slice \(Updater.currentVersion)"
        }
    }

    @ViewBuilder private var detail: some View {
        switch updater.phase {
        case .checking:
            Text("Checking for updates…")
        case .upToDate:
            Text("You're up to date.")
        case .available:
            Text("You have \(Updater.currentVersion).")
        case let .downloading(_, received, total):
            Text(total > 0 ? "\(received * 100 / total)% · \(UpdateCard.size(received)) of \(UpdateCard.size(total))"
                : "Downloading in the background")
        case .preparing:
            Text("Checking and unpacking the download…")
        case .ready:
            Text(updater.busyReason ?? "Installs when you quit Slice, or now with a relaunch.")
        case .installing:
            Text("Slice relaunches in a moment.")
        case .idle, .failed:
            if let checked = updater.lastChecked {
                Text("Last checked \(checked, format: .relative(presentation: .named))")
            } else {
                Text("Not checked yet")
            }
        }
    }

    @ViewBuilder private var button: some View {
        switch updater.phase {
        case .checking, .preparing, .installing:
            ProgressView().controlSize(.small)
        case .available:
            Button("Update Now") { updater.updateNow() }
                .buttonStyle(.borderedProminent)
                .disabled(!updater.canCheck && updater.reply == nil)
        case .downloading:
            if updater.canCancel { Button("Cancel") { updater.cancel() } }
        case .ready:
            Button("Install & Relaunch") { updater.installAndRelaunch() }
                .buttonStyle(.borderedProminent)
                .disabled(updater.busyReason != nil)
        case .failed:
            Button("Try Again") { updater.retry() }.disabled(!updater.canCheck)
        case .idle, .upToDate:
            Button("Check for Updates") { updater.checkNow() }.disabled(!updater.canCheck)
        }
    }

    @ViewBuilder private var progress: some View {
        switch updater.phase {
        case let .downloading(_, received, total) where total > 0:
            ProgressView(value: Double(received), total: Double(total))
        case .downloading, .preparing:
            ProgressView().progressViewStyle(.linear)
        case let .failed(message, _):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }
}
