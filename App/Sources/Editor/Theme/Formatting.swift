//
//  Formatting.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import SliceCore
import SwiftUI

extension OutputAspect {
    var name: String {
        switch self {
        case .auto: "Auto"
        case .landscape16x9: "Wide"
        case .portrait9x16: "Vertical"
        case .square1x1: "Square"
        }
    }

    var menuTitle: String { self == .auto ? "Auto (match recording)" : "\(name)  \(rawValue)" }

    var symbol: String {
        switch self {
        case .auto: "aspectratio"
        case .landscape16x9: "rectangle"
        case .portrait9x16: "rectangle.portrait"
        case .square1x1: "square"
        }
    }
}

func percent(_ v: Double, of range: ClosedRange<Double>) -> String {
    "\(Int(((v - range.lowerBound) / (range.upperBound - range.lowerBound) * 100).rounded()))%"
}

func format(_ s: Double) -> String {
    let s = max(s, 0)
    return String(format: "%d:%02d.%d", Int(s) / 60, Int(s) % 60, Int((s * 10).truncatingRemainder(dividingBy: 10)))
}
