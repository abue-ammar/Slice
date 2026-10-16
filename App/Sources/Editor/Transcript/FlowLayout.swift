//
//  FlowLayout.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import AppKit
import SliceCore
import SwiftUI

private struct StartsNewLine: LayoutValueKey {
    static let defaultValue = false
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 300, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (i, p) in result.positions.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        var positions: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            let paragraph = sub[StartsNewLine.self]
            if x > 0 && (x + size.width > width || paragraph) {
                y += lineHeight + lineSpacing + (paragraph ? 8 : 0)
                x = 0
                lineHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            maxX = max(maxX, x)
        }
        return (positions, CGSize(width: min(maxX, width), height: y + lineHeight))
    }
}
