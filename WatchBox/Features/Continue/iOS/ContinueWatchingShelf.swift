//
//  ContinueWatchingShelf.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI

struct ContinueWatchingShelf: View {
    let items: [WatchProgress]
    @Environment(AppSettings.self) private var settings
    @Environment(DownloadStore.self) private var downloads
    @Environment(WatchProgressStore.self) private var progressStore
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var streamer = StreamCoordinator()

    private func isDownloaded(_ item: WatchProgress) -> Bool {
        downloads.isDownloaded(mediaID: item.id, episodeLabel: item.downloadEpisodeLabel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Platform.isMac ? 14 : 10) {
            Text("Continue Watching")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            HorizontalShelfScroller {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        let canResume = streamer.canResume(item, downloads: downloads)
                        let card = ContinueWatchingCard(item: item, isDownloaded: isDownloaded(item),
                                                        showsPlayBadge: canResume)
                            .frame(width: PosterMetrics.shelfWidth(sizeClass))
                        Group {
                            if canResume {
                                Button { streamer.resume(item, downloads: downloads) } label: { card }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        PosterLink(item: item.mediaResult) {
                                            Label("View Details", systemImage: "info.circle")
                                        }
                                        removeButton(item)
                                    }
                            } else {
                                PosterLink(item: item.mediaResult) { card }
                                    .contextMenu { removeButton(item) }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
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

private struct ContinueWatchingCard: View {
    let item: WatchProgress
    var isDownloaded = false
    var showsPlayBadge = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            PosterImage(url: item.posterURL)
                .overlay(alignment: .bottom) { progressBar }
                .overlay(alignment: .topLeading) { downloadBadge }
                .overlay(alignment: .topTrailing) { playBadge }

            if Platform.isMac {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(.white)
                Text(item.episodeLabel ?? " ")
                    .font(.footnote)
                    .lineLimit(1, reservesSpace: true)
                    .foregroundStyle(.white.opacity(0.65))
            } else {
                Text(item.episodeLabel ?? item.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(item.title)
    }

    @ViewBuilder
    private var progressBar: some View {
        if item.fraction > 0 {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.5))
                    Capsule().fill(Theme.accent)
                        .frame(width: max(3, geo.size.width * item.fraction))
                }
            }
            .frame(height: 4)
            .padding(6)
        }
    }

    @ViewBuilder
    private var downloadBadge: some View {
        if isDownloaded {
            Image(systemName: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.55), in: Circle())
                .padding(6)
        }
    }

    @ViewBuilder
    private var playBadge: some View {
        if showsPlayBadge {
            Image(systemName: "play.fill")
                .font(.caption2)
                .foregroundStyle(.white)
                .padding(6)
                .background(.black.opacity(0.55), in: Circle())
                .padding(6)
        }
    }
}
#endif
