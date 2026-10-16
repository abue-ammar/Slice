//
//  IPhoneMirroring.swift
//  Slice
//
//  Created by rit3zh CX on 10/11/26.
//

import AppKit

@MainActor
final class IPhoneMirroring {
    static let bundleIdentifier = "com.apple.ScreenContinuity"
    private var cached: (bounds: CGRect?, at: TimeInterval)?

    func screenRect(aspect: CGFloat) -> CGRect? {
        let now = ProcessInfo.processInfo.systemUptime
        if cached == nil || now - cached!.at > 0.25 { cached = (Self.windowBounds(), now) }
        guard let bounds = cached?.bounds, aspect > 0 else { return nil }
        let w = min(bounds.width, bounds.height * aspect), h = w / aspect
        return CGRect(x: bounds.midX - w / 2, y: bounds.midY - h / 2, width: w, height: h)
    }

    private static func windowBounds() -> CGRect? {
        let pids = Set(NSWorkspace.shared.runningApplications.filter { $0.bundleIdentifier == bundleIdentifier }.map(\.processIdentifier))
        guard !pids.isEmpty,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return nil }
        return list.compactMap { info -> CGRect? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: dict), rect.width > 100, rect.height > 100 else { return nil }
            return rect
        }.max { $0.width * $0.height < $1.width * $1.height }
    }
}
