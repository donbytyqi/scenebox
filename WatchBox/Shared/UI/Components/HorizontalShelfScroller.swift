//
//  HorizontalShelfScroller.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI

struct HorizontalShelfScroller<Content: View>: View {
    @ViewBuilder var content: Content

    @State private var position = ScrollPosition(edge: .leading)
    @State private var offsetX: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var hovering = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content
        }
        .scrollPosition($position)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
            ScrollMetrics(offset: geo.contentOffset.x, viewport: geo.containerSize.width,
                          content: geo.contentSize.width)
        } action: { _, metrics in
            offsetX = metrics.offset
            viewportWidth = metrics.viewport
            contentWidth = metrics.content
        }
        .overlay {
            if Platform.isMac {
                HStack {
                    pager(direction: -1, systemImage: "chevron.left")
                    Spacer()
                    pager(direction: 1, systemImage: "chevron.right")
                }
                .padding(.horizontal, 6)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
            }
        }
        #if os(iOS)
        .onHover { hovering = $0 }
        #endif
    }

    private struct ScrollMetrics: Equatable {
        let offset: CGFloat
        let viewport: CGFloat
        let content: CGFloat
    }

    private var canPageBack: Bool { offsetX > 1 }
    private var canPageForward: Bool { offsetX + viewportWidth < contentWidth - 1 }

    @ViewBuilder
    private func pager(direction: CGFloat, systemImage: String) -> some View {
        let enabled = direction < 0 ? canPageBack : canPageForward
        Button {
            let step = max(viewportWidth - 120, 200) * direction
            let target = min(max(0, offsetX + step), max(0, contentWidth - viewportWidth))
            withAnimation(.easeInOut(duration: 0.3)) { position.scrollTo(x: target) }
        } label: {
            Image(systemName: systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 88)
                .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0)
        .allowsHitTesting(enabled)
    }
}
