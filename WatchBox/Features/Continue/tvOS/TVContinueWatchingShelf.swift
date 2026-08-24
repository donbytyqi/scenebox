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
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadStore.self) private var downloads
    @Environment(WatchProgressStore.self) private var progressStore
    @Environment(WatchlistStore.self) private var watchlist
    @State private var streamer = StreamCoordinator()

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
                        let canResume = streamer.canResume(item, downloads: downloads)
                        let card = TVContinueWatchingCard(item: item, isDownloaded: isDownloaded(item),
                                                          showsPlayBadge: canResume)
                        Group {
                            if canResume {
                                Button { streamer.resume(item, downloads: downloads) } label: { card }
                                    .buttonStyle(TVPosterButtonStyle(ring: false))
                                    .contextMenu {
                                        NavigationLink(value: item.mediaResult) {
                                            Label("View Details", systemImage: "info.circle")
                                        }
                                        removeButton(item)
                                    }
                            } else {
                                NavigationLink(value: item.mediaResult) { card }
                                    .buttonStyle(TVPosterButtonStyle(ring: false))
                                    .contextMenu { removeButton(item) }
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
        .fullScreenCover(isPresented: Binding(get: { streamer.isPresenting },
                                              set: { if !$0 { streamer.stop() } })) {
            StreamPlayerContainer(streamer: streamer)
                .environment(settings)
                .environment(downloads)
                .environment(progressStore)
                .environment(watchlist)
        }
    }

    private func removeButton(_ item: WatchProgress) -> some View {
        Button(role: .destructive) {
            WatchProgressStore.shared.remove(id: item.id)
        } label: {
            Label("Remove", systemImage: "xmark.circle")
        }
    }
}

private struct TVContinueWatchingCard: View {
    let item: WatchProgress
    var isDownloaded = false
    var showsPlayBadge = false
    private let width: CGFloat = 260
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImage(url: item.posterURL)
                .frame(width: width)
                .overlay(alignment: .bottom) { progressBar }
                .overlay(alignment: .topLeading) { downloadBadge }
                .overlay(alignment: .topTrailing) { playBadge }
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

    @ViewBuilder
    private var playBadge: some View {
        if showsPlayBadge {
            Image(systemName: "play.fill")
                .font(.callout)
                .foregroundStyle(.white)
                .padding(8)
                .background(.black.opacity(0.55), in: Circle())
                .padding(8)
        }
    }
}
#endif
