//
//  TVEpisodeCard.swift
//  SceneBox
//
//  Created by SpontaneousArray on 16.08.26.
//

#if os(tvOS)
import SwiftUI
import Kingfisher

struct TVEpisodeCard: View {
    let episode: Episode
    var isDownloaded = false
    var isWatched = false
    var progress: Double? = nil

    static let width: CGFloat = 330
    static let stillHeight: CGFloat = width * 9 / 16
    static let height: CGFloat = stillHeight + 8 + 30 + 4 + 56
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            still
                .overlay { TVFocusRing(cornerRadius: 12, isFocused: isFocused) }
            Text("\(episode.episode). \(episode.name)")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(episode.overview?.isEmpty == false ? episode.overview! : " ")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(2, reservesSpace: true)
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .accessibilityLabel("Episode \(episode.episode), \(episode.name)")
    }

    private var still: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.surface)
            .frame(width: Self.width, height: Self.stillHeight)
            .overlay {
                KFImage(episode.thumbnailURL)
                    .resizable()
                    .fade(duration: 0.2)
                    .placeholder {
                        Image(systemName: "photo").font(.title).foregroundStyle(.white.opacity(0.2))
                    }
                    .scaledToFill()
                    .opacity(isWatched ? 0.55 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(.white, Theme.accent)
                        .padding(10)
                        .accessibilityLabel("Watched")
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 8) {
                    if isDownloaded {
                        Image(systemName: "arrow.down.circle.fill")
                    }
                    if let released = episode.released {
                        Text(released.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(10)
                .opacity(isDownloaded || episode.released != nil ? 1 : 0)
            }
            .overlay(alignment: .bottom) {
                if let progress {
                    GeometryReader { geo in
                        Capsule().fill(.white.opacity(0.35))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Theme.accent)
                                    .frame(width: geo.size.width * min(max(progress, 0), 1))
                            }
                    }
                    .frame(height: 5)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(22)
                    .background(.black.opacity(0.5), in: Circle())
                    .opacity(isFocused ? 1 : 0)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
#endif
