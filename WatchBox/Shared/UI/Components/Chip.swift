//
//  Chip.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import SwiftUI

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .white

    @Environment(\.isFocused) private var isFocused

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text)
        }
        .lineLimit(1)
        .fixedSize()
        .font(font)
        .foregroundStyle(isFocused && tint == .white ? .black : tint)
        .padding(.horizontal, hPad)
        .padding(.vertical, vPad)
        .background(isFocused ? Color.black.opacity(0.08) : Color.white.opacity(0.12), in: Capsule())
    }

    #if os(tvOS)
    private var font: Font { .title3.weight(.medium) }
    private var hPad: CGFloat { 18 }
    private var vPad: CGFloat { 10 }
    #else
    private var font: Font { .caption.weight(.medium) }
    private var hPad: CGFloat { 10 }
    private var vPad: CGFloat { 5 }
    #endif
}
