//
//  TVEpisodePanel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

#if os(tvOS)
import SwiftUI
import Kingfisher

struct TVEpisodePanel: View {
    let episodes: EpisodePlaylist
    let onPlay: (Episode) -> Void
    let onClose: () -> Void

    @State private var season: Int
    @FocusState private var focus: Focus?

    private enum Focus: Hashable { case close, season(Int), episode(String) }

    init(episodes: EpisodePlaylist,
         onPlay: @escaping (Episode) -> Void,
         onClose: @escaping () -> Void) {
        self.episodes = episodes
        self.onPlay = onPlay
        self.onClose = onClose
        _season = State(initialValue: episodes.current.season)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 22) {
                header
                if episodes.seasons.count > 1 { seasonRow }
                episodeList
            }
            .padding(28)
            .frame(maxWidth: 760, maxHeight: .infinity, alignment: .leading)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .padding(48)
        }
        .foregroundStyle(.white)
        .defaultFocus($focus, .episode(episodes.current.id))
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack {
            Text("Episodes").font(.title2.weight(.bold))
            Spacer()
            Button(action: onClose) { Image(systemName: "xmark") }
                .buttonStyle(TVCircleButtonStyle(diameter: 46))
                .focused($focus, equals: .close)
        }
    }

    private var seasonRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(episodes.seasons, id: \.self) { s in
                    Button { season = s } label: {
                        Text(s == 0 ? "Specials" : "Season \(s)")
                    }
                    .buttonStyle(SeasonChipStyle(selected: s == season))
                    .focused($focus, equals: .season(s))
                }
            }
            .padding(.vertical, 4)
        }
        .focusSection()
    }

    private var episodeList: some View {
        ScrollView {
            VStack(spacing: 10) {
                ForEach(episodes.episodes(inSeason: season)) { episode in
                    Button { onPlay(episode) } label: { EmptyView() }
                        .buttonStyle(EpisodeRowStyle(episode: episode,
                                                     isCurrent: episode.id == episodes.current.id))
                        .focused($focus, equals: .episode(episode.id))
                }
            }
            .padding(.vertical, 4)
        }
        .focusSection()
    }
}

private struct SeasonChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Chip(label: configuration.label, selected: selected)
    }

    struct Chip<Label: View>: View {
        let label: Label
        let selected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            label
                .font(.headline)
                .foregroundStyle(isFocused ? .black : .white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(background, in: Capsule())
                .overlay(
                    Capsule().stroke(.white.opacity(selected && !isFocused ? 0.5 : 0), lineWidth: 2)
                )
                .scaleEffect(isFocused ? 1.04 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var background: Color {
            if isFocused { return .white }
            return selected ? .white.opacity(0.18) : .white.opacity(0.06)
        }
    }
}

private struct EpisodeRowStyle: ButtonStyle {
    let episode: Episode
    let isCurrent: Bool

    func makeBody(configuration: Configuration) -> some View {
        Row(episode: episode, isCurrent: isCurrent)
    }

    struct Row: View {
        let episode: Episode
        let isCurrent: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(alignment: .top, spacing: 18) {
                thumbnail

                VStack(alignment: .leading, spacing: 5) {
                    Text("\(episode.episode). \(episode.name)")
                        .font(.title3.weight(.semibold))
                        .lineLimit(1)
                    if let overview = episode.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.callout)
                            .foregroundStyle(isFocused ? .black.opacity(0.7) : .white.opacity(0.6))
                            .lineLimit(2)
                    }
                    if let released = episode.released {
                        Text(released.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(isFocused ? .black.opacity(0.55) : .white.opacity(0.4))
                    }
                }

                Spacer(minLength: 8)

                if isCurrent {
                    Image(systemName: "play.fill").font(.title3)
                }
            }
            .foregroundStyle(isFocused ? .black : .white)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .scaleEffect(isFocused ? 1.01 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var thumbnail: some View {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.black.opacity(0.25))
                .frame(width: 160, height: 90)
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
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }

        private var background: Color {
            if isFocused { return .white }
            return isCurrent ? .white.opacity(0.14) : .white.opacity(0.06)
        }
    }
}
#endif
