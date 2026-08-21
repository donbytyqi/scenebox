//
//  TVDetailView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

#if os(tvOS)
import SwiftUI
import Kingfisher

struct TVDetailView: View {
    let detail: MediaDetail
    let fallbackTitle: String
    let isBusy: Bool
    var cast: [CastMember] = []
    @Binding var selectedSeason: Int
    var resumeEpisode: Episode? = nil
    var watchLabel: String? = nil
    var watchProgress: Double? = nil
    var watchedEpisodes: Set<String> = []
    var similar: [MediaResult] = []
    let onWatch: (Episode?) -> Void
    let onDownload: (Episode?) -> Void
    var onSetWatched: (Episode, Bool) -> Void = { _, _ in }

    @Environment(DownloadStore.self) private var downloads
    @Environment(WatchlistStore.self) private var watchlist
    @FocusState private var focus: Focusable?
    @State private var shelf: Shelf = .episodes
    @State private var showingSynopsis = false
    @FocusState private var focusedEpisodeID: String?
    @State private var detailEpisode: Episode?

    private enum Focusable: Hashable { case watch, download, watchlist, synopsis }
    private enum Shelf: Hashable { case episodes, cast, similar }

    private static let edge: CGFloat = 90
    private static let columnWidth: CGFloat = 1120

    var body: some View {
        ZStack(alignment: .topLeading) {
            backdrop

            VStack(alignment: .leading, spacing: 0) {
                infoColumn
                    .frame(width: Self.columnWidth, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
                if hasShelf { bottomShelf }
            }
            .padding(.horizontal, Self.edge)
            .padding(.top, 52)
            .padding(.bottom, 40)

            focusedEpisodePanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .ignoresSafeArea()
        .defaultFocus($focus, .watch)
        .animation(.easeOut(duration: 0.15), value: focusedEpisodeID)
        .onAppear {
            if !hasEpisodes { shelf = hasCast ? .cast : .similar }
        }
        .onChange(of: similar.isEmpty) { _, empty in
            if !empty, !hasEpisodes, !hasCast { shelf = .similar }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(120))
            if !Task.isCancelled { focus = .watch }
        }
        .sheet(isPresented: $showingSynopsis) { synopsisSheet }
        .sheet(item: $detailEpisode) { episode in
            TVReadableSheet(title: "\(episode.label) · \(episode.name)",
                            paragraphs: Self.paragraphs(of: episode.overview ?? ""),
                            footnote: episode.released.map { $0.formatted(date: .long, time: .omitted) })
        }
    }

    @ViewBuilder
    private var focusedEpisodePanel: some View {
        let episode = focusedEpisodeID.flatMap { id in detail.episodes.first { $0.id == id } }
        let overview = episode?.overview ?? ""
        if let episode, shelf == .episodes, !overview.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(episode.label) · \(episode.name)")
                    .font(.headline)
                    .lineLimit(2)
                Text(overview)
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(9)
                if let released = episode.released {
                    Text(released.formatted(date: .long, time: .omitted))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .foregroundStyle(.white)
            .padding(28)
            .frame(width: 600, alignment: .leading)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, Self.edge)
            .padding(.top, 240)
            .transition(.opacity)
            .allowsHitTesting(false)
            .id(episode.id)
        }
    }

    private static func paragraphs(of text: String) -> [String] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let explicit = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if explicit.count > 1 { return explicit }

        var chunks: [String] = []
        var current = ""
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            current += sentence
            if current.count >= 320 {
                chunks.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            chunks.append(current.trimmingCharacters(in: .whitespaces))
        }
        return chunks.isEmpty ? [text] : chunks
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            TVBackdropImage(url: detail.backdropURL)
            Color.black.opacity(0.45)
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.6), location: 0.0),
                    .init(color: .black.opacity(0.3), location: 0.45),
                    .init(color: .clear, location: 0.75),
                ],
                startPoint: .leading, endPoint: .trailing)
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.0),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.7), location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Info column

    private var infoColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            TVTitleArt(logoURL: detail.logoURL,
                       title: detail.name.isEmpty ? fallbackTitle : detail.name,
                       maxLogoWidth: 520, maxLogoHeight: 130, titleSize: 56)
            metadataChips
            synopsis
            credits
            actions
        }
    }

    private var metadataChips: some View {
        HStack(spacing: 12) {
            if let rating = detail.imdbRating {
                Chip(text: String(format: "%.1f", rating), systemImage: "star.fill", tint: .yellow)
            }
            if let year = detail.year, !year.isEmpty {
                Chip(text: year, systemImage: "calendar")
            }
            if let runtime = detail.runtime {
                Chip(text: runtime, systemImage: "clock")
            }
            if detail.type == .series, !detail.seasons.isEmpty {
                let count = detail.seasons.filter { $0 > 0 }.count
                Chip(text: count == 1 ? "1 Season" : "\(count) Seasons", systemImage: "square.stack")
            }
            ForEach(detail.genres.prefix(3), id: \.self) { genre in
                Chip(text: genre)
            }
        }
    }

    @ViewBuilder
    private var synopsis: some View {
        if let text = detail.description, !text.isEmpty {
            let lines = hasShelf ? 4 : 6
            Button {
                showingSynopsis = true
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(text)
                        .font(.body)
                        .lineSpacing(3)
                        .lineLimit(lines)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if text.count > lines * 90 {
                        Label("More", systemImage: "chevron.right")
                            .font(.callout.weight(.semibold))
                            .labelStyle(TrailingIconLabelStyle())
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(TVSynopsisButtonStyle())
            .focused($focus, equals: .synopsis)
        }
    }

    private var credits: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !detail.cast.isEmpty {
                creditLine("Starring", detail.cast.prefix(4).joined(separator: ", "))
            }
            if !detail.directors.isEmpty {
                creditLine(detail.directors.count > 1 ? "Directors" : "Director",
                           detail.directors.prefix(3).joined(separator: ", "))
            } else if !detail.writers.isEmpty {
                creditLine(detail.writers.count > 1 ? "Writers" : "Writer",
                           detail.writers.prefix(3).joined(separator: ", "))
            }
        }
    }

    private func creditLine(_ label: String, _ value: String) -> some View {
        Text("\(Text(label + "  ").foregroundStyle(.white.opacity(0.45)))\(Text(value).foregroundStyle(.white.opacity(0.85)))")
            .font(.callout)
            .lineLimit(1)
    }

    private var actions: some View {
        HStack(spacing: 20) {
            Button {
                onWatch(resumeEpisode ?? primaryEpisode)
            } label: {
                VStack(spacing: 10) {
                    Label(watchLabel ?? watchTitle, systemImage: "play.fill")
                        .lineLimit(1)
                        .fixedSize()
                    if let watchProgress {
                        WatchProgressBar(fraction: watchProgress)
                            .frame(maxWidth: .infinity)
                            .frame(height: 4)
                    }
                }
                .frame(minWidth: 240)
                .padding(.horizontal, 8)
                .padding(.vertical, watchProgress != nil ? 4 : 0)
            }
            .buttonStyle(TVAccentButtonStyle())
            .focused($focus, equals: .watch)

            Button {
                onDownload(resumeEpisode ?? primaryEpisode)
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(TVAccentButtonStyle())
            .focused($focus, equals: .download)

            Button {
                watchlist.toggle(id: detail.id, mediaType: detail.type,
                                 title: detail.name.isEmpty ? fallbackTitle : detail.name,
                                 posterURL: detail.posterURL)
            } label: {
                Label(isSaved ? "In Watchlist" : "Watchlist",
                      systemImage: isSaved ? "bookmark.fill" : "bookmark")
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(TVAccentButtonStyle(selected: isSaved))
            .focused($focus, equals: .watchlist)
        }
        .fixedSize()
        .disabled(isBusy)
        .padding(.top, 4)
        .focusSection()
    }

    private var isSaved: Bool { watchlist.contains(detail.id) }

    private var primaryEpisode: Episode? {
        guard detail.type == .series else { return nil }
        return detail.episodes(inSeason: selectedSeason).first
    }

    private var watchTitle: String {
        guard detail.type == .series, let episode = primaryEpisode else { return "Watch" }
        return "Watch · \(episode.label)"
    }

    // MARK: - Bottom shelf

    private var hasEpisodes: Bool { detail.type == .series && !detail.seasons.isEmpty }
    private var hasCast: Bool { !cast.isEmpty || !detail.cast.isEmpty }
    private var hasSimilar: Bool { !similar.isEmpty }
    private var hasShelf: Bool { hasEpisodes || hasCast || hasSimilar }
    private var shelfCount: Int { [hasEpisodes, hasCast, hasSimilar].filter { $0 }.count }

    private var bottomShelf: some View {
        VStack(alignment: .leading, spacing: 14) {
            shelfHeader
            Group {
                switch shelf {
                case .episodes: episodeShelf
                case .cast: castShelf
                case .similar: similarShelf
                }
            }
            .frame(height: shelfHeight)
        }
        .focusSection()
    }

    private var shelfHeight: CGFloat { TVEpisodeCard.height + 36 }

    private var shelfHeader: some View {
        HStack(spacing: 16) {
            if shelfCount > 1 {
                if hasEpisodes { shelfTab("Episodes", .episodes) }
                if hasCast { shelfTab("Cast", .cast) }
                if hasSimilar { shelfTab("More Like This", .similar) }
            } else {
                Text(hasEpisodes ? "Episodes" : hasCast ? "Cast" : "More Like This")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
            }
            Spacer()
            if hasEpisodes, shelf == .episodes {
                Menu {
                    Picker("Season", selection: $selectedSeason) {
                        ForEach(detail.seasons, id: \.self) { season in
                            Text(seasonName(season)).tag(season)
                        }
                    }
                } label: {
                    Label(seasonName(selectedSeason), systemImage: "chevron.down")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(TVAccentButtonStyle())
            }
        }
        .padding(.trailing, 4)
        .focusSection()
    }

    private func shelfTab(_ title: String, _ value: Shelf) -> some View {
        Button { shelf = value } label: { Text(title) }
            .buttonStyle(TVAccentButtonStyle(selected: shelf == value))
    }

    private func seasonName(_ season: Int) -> String {
        season == 0 ? "Specials" : "Season \(season)"
    }

    @ViewBuilder
    private var episodeShelf: some View {
        let episodes = detail.episodes(inSeason: selectedSeason)
        if episodes.isEmpty {
            Text("No episodes listed for this season.")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 32) {
                    ForEach(episodes) { episode in
                        Button {
                            onWatch(episode)
                        } label: {
                            TVEpisodeCard(
                                episode: episode,
                                isDownloaded: downloads.isDownloaded(mediaID: detail.id,
                                                                     episodeLabel: episode.label),
                                isWatched: watchedEpisodes.contains(episode.label),
                                progress: episode.id == resumeEpisode?.id ? watchProgress : nil)
                        }
                        .buttonStyle(TVPosterButtonStyle(ring: false, scale: 1.05))
                        .focused($focusedEpisodeID, equals: episode.id)
                        .contextMenu {
                            if let overview = episode.overview, !overview.isEmpty {
                                Button { detailEpisode = episode } label: {
                                    Label("Show Details", systemImage: "text.alignleft")
                                }
                            }
                            let watched = watchedEpisodes.contains(episode.label)
                            Button { onSetWatched(episode, !watched) } label: {
                                Label(watched ? "Mark as Unwatched" : "Mark as Watched",
                                      systemImage: watched ? "eye.slash" : "checkmark.circle")
                            }
                            Button { onDownload(episode) } label: {
                                Label("Download", systemImage: "arrow.down.circle")
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)   // room for the focus lift
                .padding(.vertical, 18)
            }
            .padding(.horizontal, -20)
            .scrollClipDisabled()
            .id(selectedSeason)         // fresh row (and scroll offset) per season
        }
    }

    private var castShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 28) {
                if cast.isEmpty {
                    ForEach(detail.cast.prefix(12), id: \.self) { name in
                        castTile(name: name, role: nil, photo: nil)
                    }
                } else {
                    ForEach(cast) { member in
                        NavigationLink(value: member) {
                            castTile(name: member.name, role: member.role, photo: member.photoURL)
                        }
                        .buttonStyle(TVPosterButtonStyle(ring: false, scale: 1.06))
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .padding(.horizontal, -20)
        .scrollClipDisabled()
    }

    private var similarShelf: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 36) {
                ForEach(similar) { item in
                    NavigationLink(value: item) {
                        TVPosterCard(item: item, width: 186)
                    }
                    .buttonStyle(TVPosterButtonStyle())
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
        }
        .padding(.horizontal, -20)
        .scrollClipDisabled()
    }

    private func castTile(name: String, role: String?, photo: URL?) -> some View {
        VStack(spacing: 10) {
            Circle()
                .fill(Theme.surface)
                .frame(width: 150, height: 150)
                .overlay {
                    if let photo {
                        KFImage(photo)
                            .resizable()
                            .placeholder { initialsLabel(name) }
                            .scaledToFill()
                    } else {
                        initialsLabel(name)
                    }
                }
                .clipShape(Circle())
            Text(name)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: 160)
            Text(role?.isEmpty == false ? role! : " ")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .frame(width: 160)
        }
    }

    private func initialsLabel(_ name: String) -> some View {
        Text(Self.initials(name))
            .font(.title3.weight(.semibold))
            .foregroundStyle(.white.opacity(0.7))
    }

    private static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }

    // MARK: - Full synopsis

    private var synopsisSheet: some View {
        var footnotes: [String] = []
        if let awards = detail.awards, !awards.isEmpty { footnotes.append("Awards: " + awards) }
        if let country = detail.country, !country.isEmpty { footnotes.append("Country: " + country) }
        return TVReadableSheet(title: detail.name.isEmpty ? fallbackTitle : detail.name,
                               paragraphs: Self.paragraphs(of: detail.description ?? ""),
                               footnote: footnotes.isEmpty ? nil : footnotes.joined(separator: "\n"))
    }
}

private struct TVReadableSheet: View {
    let title: String
    let paragraphs: [String]
    var footnote: String? = nil

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        TVReadableParagraph(text: paragraph)
                    }
                    if let footnote {
                        TVReadableParagraph(text: footnote, secondary: true)
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
                .padding(80)
            }
        }
        .foregroundStyle(.white)
    }
}

private struct TVReadableParagraph: View {
    let text: String
    var secondary = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Text(text)
            .font(.title3)
            .lineSpacing(6)
            .foregroundStyle(.white.opacity(secondary ? 0.6 : (isFocused ? 1 : 0.8)))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(isFocused ? Color.white.opacity(0.08) : .clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(-16)
            .focusable()
            .focused($isFocused)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct TVSynopsisButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    struct Content: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .foregroundStyle(.white.opacity(isFocused ? 1 : 0.85))
                .padding(12)
                .background(isFocused ? Color.white.opacity(0.1) : .clear,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(-12)
                .scaleEffect(isFocused ? 1.01 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

private struct TrailingIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.title
            configuration.icon.font(.caption.weight(.bold))
        }
    }
}
#endif
