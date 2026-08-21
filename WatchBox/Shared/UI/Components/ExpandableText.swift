//
//  ExpandableText.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import SwiftUI

struct ExpandableText: View {
    let text: String
    var lineLimit: Int = 3
    var font: Font = .caption
    var color: Color = .secondary

    @State private var expanded = false
    @State private var collapsedHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0

    private var isTruncatable: Bool { fullHeight > collapsedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(expanded ? nil : lineLimit)
                .background(measurement)

            if isTruncatable {
                Button(expanded ? "Show less" : "Show more") {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                }
                .font(font.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
            }
        }
    }

    private var measurement: some View {
        ZStack {
            Text(text)
                .font(font)
                .lineLimit(lineLimit)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { collapsedHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, height in collapsedHeight = height }
                })
            Text(text)
                .font(font)
                .fixedSize(horizontal: false, vertical: true)
                .background(GeometryReader { geo in
                    Color.clear
                        .onAppear { fullHeight = geo.size.height }
                        .onChange(of: geo.size.height) { _, height in fullHeight = height }
                })
        }
        .hidden()
        .accessibilityHidden(true)
    }
}
