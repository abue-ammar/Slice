//
//  KeyCap.swift
//  Slice
//
//  Created by rit3zh CX on 10/4/26.
//

import SliceCore
import SwiftUI

struct KeyCap: View {
    let key: String
    var pressed = false
    var large = false

    var body: some View {
        let size: CGFloat = large ? 26 : 20
        let radius: CGFloat = large ? 7 : 5
        let lip: CGFloat = pressed ? 0.5 : (large ? 2.5 : 2)
        Text(key)
            .font(.rounded(large ? 13 : (key.count > 1 ? 10 : 11), .medium))
            .foregroundStyle(pressed ? Theme.accent : Color.primary.opacity(0.8))
            .padding(.horizontal, large ? 7 : 5)
            .padding(.bottom, lip)
            .frame(minWidth: size, minHeight: size)
            .background {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.black.opacity(0.35))
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(pressed ? Theme.accent.opacity(0.22) : Color(white: 0.2))
                        .padding(.bottom, lip)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(pressed ? Theme.accent.opacity(0.5) : Color.white.opacity(0.08)))
            .offset(y: pressed ? 1 : 0)
            .animation(.snappy(duration: 0.1), value: pressed)
    }
}

struct KeyCombo: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in KeyCap(key: key) }
        }
    }
}
