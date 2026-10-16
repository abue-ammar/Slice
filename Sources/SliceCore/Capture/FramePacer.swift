//
//  FramePacer.swift
//  SliceCore
//
//  Created by rit3zh CX on 10/11/26.
//

import CoreMedia

/// Picks which screen frames a recording keeps, so it runs at its frame rate with every frame on time.
///
/// Frames arrive on display refreshes, give or take a little jitter. ScreenCaptureKit can cap the rate itself
/// (`minimumFrameInterval`), but its cap runs on a fixed cadence: a refresh landing a hair before its slot is skipped
/// and the next one taken, which at exactly the display's rate loses about one frame in twenty and below it spaces
/// frames unevenly. Either shows as stutter in scrolling and animation. So the stream is asked for every refresh
/// (`streamInterval`) and the recording picks from those itself, measuring from the last frame kept, with half a
/// refresh of tolerance for the jitter.
public struct FramePacer: Sendable {
    public enum Decision: Equatable, Sendable {
        case hold
        case keep
        case keepHeldAndThis
    }

    let spacing: Double
    let late: Double
    private var last: Double?
    private var holding = false

    public init(fps: Int, refreshRate: Int) {
        let period = 1 / Double(max(fps, 1))
        let tolerance = 0.5 / Double(max(refreshRate, fps, 1))
        spacing = period - tolerance
        late = period + tolerance
    }

    public static func streamInterval(refreshRate: Int) -> CMTime {
        CMTime(value: 1, timescale: CMTimeScale(max(refreshRate, 1) * 2))
    }

    public mutating func offer(_ time: Double) -> Decision {
        guard let last else {
            self.last = time
            return .keep
        }
        let gap = time - last
        if gap < spacing {
            holding = true
            return .hold
        }
        defer {
            self.last = time
            holding = false
        }
        return holding && gap > late ? .keepHeldAndThis : .keep
    }
}
