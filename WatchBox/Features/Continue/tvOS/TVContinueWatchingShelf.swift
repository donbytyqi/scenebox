//
//  TVContinueWatchingShelf.swift
//  SceneBox
//
//  Created by SpontaneousArray on 01.08.26.
//

#if os(tvOS)
import SwiftUI

struct TVContinueWatchingShelf: View {
    let items: [WatchProgress]
    @Environment(DownloadStore.self) private var downloads

    private func isDownloaded(_ item: WatchProgress) -> Bool {
        downloads.isDownloaded(mediaID: item.id, episodeLabel: item.downloadEpisodeLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Continue Watching")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, TVHomeView.edge)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { item in
                        NavigationLink(value: item.mediaResult) {
                            TVContinueWatchingCard(item: item, isDownloaded: isDownloaded(item))
                        }
                        .buttonStyle(TVPosterButtonStyle(ring: false))
                        .contextMenu {
                            Button(role: .destructive) {
                                WatchProgressStore.shared.remove(id: item.id)
                            } label: {
                                Label("Remove", systemImage: "xmark.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal, TVHomeView.edge)
                .padding(.vertical, 44)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

private struct TVContinueWatchingCard: View {
    let item: WatchProgress
    var isDownloaded = false
    private let width: CGFloat = 260
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImage(url: item.posterURL)
                .frame(width: width)
                .overlay(alignment: .bottom) { progressBar }
                .overlay(alignment: .topLeading) { downloadBadge }
                .overlay { TVFocusRing(cornerRadius: Theme.posterCorner, isFocused: isFocused) }

            Text(item.episodeLabel ?? item.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: width, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityLabel(item.title)
    }

    @ViewBuilder
    private var progressBar: some View {
        if item.fraction > 0 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.5))
                    Capsule().fill(Theme.accent)
                        .frame(width: max(4, geo.size.width * item.fraction))
                }
            }
            .frame(height: 5)
            .padding(8)
        }
    }

    @ViewBuilder
    private var downloadBadge: some View {
        if isDownloaded {
            Image(systemName: "arrow.down.circle.fill")
                .font(.body)
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.55), in: Circle())
                .padding(8)
        }
    }
}
#endif
