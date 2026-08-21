//
//  EpisodeSection.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import Kingfisher

struct EpisodeSection: View {
    let detail: MediaDetail
    @Binding var selectedSeason: Int
    var watchedEpisodes: Set<String> = []
    let onWatch: (Episode) -> Void
    let onDownload: (Episode) -> Void
    var onSetWatched: (Episode, Bool) -> Void = { _, _ in }
    @Environment(DownloadStore.self) private var downloads
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var usesCards: Bool { Platform.isMac || sizeClass == .regular }
    private var cardWidth: CGFloat { Platform.isMac ? 300 : 280 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Episodes")
                    .font(.headline)
                Spacer()
                Picker("Season", selection: $selectedSeason) {
                    ForEach(detail.seasons, id: \.self) { season in
                        Text(season == 0 ? "Specials" : "Season \(season)").tag(season)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.accent)
            }
            .padding(.horizontal, 20)

            let episodes = detail.episodes(inSeason: selectedSeason)
            if episodes.isEmpty {
                Text("No episodes listed for this season.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else if usesCards {
                HorizontalShelfScroller {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(episodes) { episode in
                            let watched = watchedEpisodes.contains(episode.label)
                            let downloaded = downloads.isDownloaded(mediaID: detail.id,
                                                                    episodeLabel: episode.label)
                            EpisodeCard(episode: episode, width: cardWidth,
                                        isDownloaded: downloaded, isWatched: watched,
                                        onWatch: { onWatch(episode) },
                                        onDownload: { onDownload(episode) })
                            .contextMenu {
                                Button { onSetWatched(episode, !watched) } label: {
                                    Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                                          systemImage: watched ? "eye.slash" : "checkmark.circle")
                                }
                                if !downloaded {
                                    Button { onDownload(episode) } label: {
                                        Label("Download", systemImage: "arrow.down.circle")
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(episodes) { episode in
                        let watched = watchedEpisodes.contains(episode.label)
                        EpisodeRow(episode: episode,
                                   isDownloaded: downloads.isDownloaded(mediaID: detail.id,
                                                                        episodeLabel: episode.label),
                                   isWatched: watched,
                                   onWatch: { onWatch(episode) },
                                   onDownload: { onDownload(episode) })
                        .contextMenu {
                            Button {
                                onSetWatched(episode, !watched)
                            } label: {
                                Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                                      systemImage: watched ? "eye.slash" : "checkmark.circle")
                            }
                        }
                        if episode.id != episodes.last?.id {
                            Divider().overlay(.white.opacity(0.08)).padding(.leading, 20)
                        }
                    }
                }
            }
        }
    }
}

private struct EpisodeRow: View {
    let episode: Episode
    var isDownloaded = false
    var isWatched = false
    let onWatch: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(episode.episode). \(episode.name)")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(2)
                    if isWatched {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Watched")
                    }
                }

                if let overview = episode.overview, !overview.isEmpty {
                    ExpandableText(text: overview, lineLimit: 3,
                                   font: .caption, color: .secondary)
                }

                if let released = episode.released {
                    Text(released.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(action: onWatch) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                Button(action: onDownload) {
                    Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(isDownloaded ? .green : .white.opacity(0.6))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .disabled(isDownloaded)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Theme.surface)
            .frame(width: 104, height: 59)
            .opacity(isWatched ? 0.55 : 1)
            .overlay {
                KFImage(episode.thumbnailURL)
                    .resizable()
                    .fade(duration: 0.2)
                    .placeholder {
                        Image(systemName: "photo")
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct EpisodeCard: View {
    let episode: Episode
    let width: CGFloat
    var isDownloaded = false
    var isWatched = false
    let onWatch: () -> Void
    let onDownload: () -> Void
    @State private var hovering = false

    private var stillHeight: CGFloat { width * 9 / 16 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onWatch) {
                still
            }
            .buttonStyle(.plain)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(episode.episode). \(episode.name)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Watched")
                }
            }
            if let overview = episode.overview, !overview.isEmpty {
                Text(overview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
            }
            if let released = episode.released {
                Text(released.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: width, alignment: .leading)
        #if os(iOS)
        .onHover { hovering = $0 }
        #endif
    }

    private var still: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Theme.surface)
            .frame(width: width, height: stillHeight)
            .overlay {
                KFImage(episode.thumbnailURL)
                    .resizable()
                    .fade(duration: 0.2)
                    .placeholder {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.white.opacity(0.2))
                    }
                    .scaledToFill()
                    .opacity(isWatched ? 0.55 : 1)
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(18)
                    .background(.black.opacity(0.5), in: Circle())
                    .opacity(Platform.isMac ? (hovering ? 1 : 0) : 0.9)
                    .animation(.easeOut(duration: 0.15), value: hovering)
            }
            .overlay(alignment: .topTrailing) {
                Button(action: onDownload) {
                    Image(systemName: isDownloaded ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isDownloaded ? .green : .white)
                        .padding(6)
                        .background(.black.opacity(0.45), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(isDownloaded)
                .padding(8)
                .accessibilityLabel(isDownloaded ? "Downloaded" : "Download")
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
