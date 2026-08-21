//
//  MediaDetailView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import Kingfisher

struct MediaDetailView: View {
    let mediaID: String
    let type: MediaType
    let fallbackTitle: String

    @State private var model: MediaDetailModel
    @State private var streamer = StreamCoordinator()
    @State private var pendingPlay: (() -> Void)?
    @State private var isAutoResolving = false
    @State private var resumeAt: Duration = .zero
    @Environment(DownloadStore.self) private var downloads
    @Environment(AppSettings.self) private var settings
    @Environment(WatchProgressStore.self) private var progressStore
    @Environment(WatchlistStore.self) private var watchlist
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dismiss) private var dismiss

    init(mediaID: String, type: MediaType, fallbackTitle: String) {
        self.mediaID = mediaID
        self.type = type
        self.fallbackTitle = fallbackTitle
        _model = State(initialValue: MediaDetailModel(mediaID: mediaID, type: type))
    }

    var body: some View {
        content
            .overlay { if isAutoResolving { resolvingOverlay } }
            .background(Theme.background)
            #if os(iOS)
            .ignoresSafeArea(edges: .top)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar(Platform.isMac ? .hidden : .automatic, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                if Platform.isMac {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.escape, modifiers: [])
                    .padding(16)
                    .accessibilityLabel("Back")
                }
            }
            #else
            .ignoresSafeArea()
            .toolbar(.hidden, for: .navigationBar)
            #endif
            .navigationTitle(Platform.isMac ? displayTitle : "")
            .inlineNavigationBar()
            #if os(iOS)
            .onChange(of: displayTitle, initial: true) { _, title in MacWindow.setTitle(title) }
            .onDisappear { MacWindow.setTitle("") }
            #endif
            .task { model.load() }
            .onDisappear {
                if !streamer.isPresenting { streamer.stop() }
            }
            #if os(tvOS)
            .fullScreenCover(item: releaseRequestBinding, onDismiss: runPendingPlay) { request in
                ReleasePickerView(model: model, request: request) { stream in
                    handle(request: request, stream: stream)
                }
                .environment(settings)
                .environment(downloads)
                .environment(progressStore)
                .environment(watchlist)
            }
            #else
            .sheet(item: releaseRequestBinding, onDismiss: runPendingPlay) { request in
                ReleasePickerView(model: model, request: request) { stream in
                    handle(request: request, stream: stream)
                }
                .environment(settings)
                .environment(downloads)
                .environment(progressStore)
                .environment(watchlist)
                .preferredColorScheme(.dark)
            }
            #endif
            .fullScreenCover(isPresented: Binding(get: { streamer.isPresenting },
                                                  set: { if !$0 { streamer.stop() } })) {
                StreamPlayerContainer(streamer: streamer)
                    .environment(settings)
                    .environment(downloads)
                    .environment(progressStore)
                    .environment(watchlist)
            }
    }

    private var displayTitle: String {
        if let name = model.detail?.name, !name.isEmpty { return name }
        return fallbackTitle
    }

    private var releaseRequestBinding: Binding<MediaDetailModel.ReleaseRequest?> {
        Binding(get: { model.releaseRequest },
                set: { if $0 == nil { model.dismissReleases() } })
    }

    private func runPendingPlay() {
        let action = pendingPlay
        pendingPlay = nil
        action?()
    }

    private var resolvingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Finding best source…")
                    .font(.callout)
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isReady, let detail = model.detail {
            #if os(tvOS)
            TVDetailView(
                detail: detail,
                fallbackTitle: fallbackTitle,
                isBusy: streamer.isPreparing,
                cast: model.castMembers,
                selectedSeason: Binding(get: { model.selectedSeason },
                                        set: { model.selectedSeason = $0 }),
                resumeEpisode: resumeEpisode(for: detail),
                watchLabel: resumeLabel(for: detail),
                watchProgress: watchProgressFraction(for: detail),
                watchedEpisodes: progressStore.watchedEpisodes(for: mediaID),
                similar: model.similar,
                onWatch: { watch(episode: $0) },
                onDownload: { requestDownload(episode: $0) },
                onSetWatched: { setWatched($1, episode: $0, detail: detail) }
            )
            #else
            detailScroll(detail)
            #endif
        } else if model.detail == nil, let message = model.errorMessage {
            EmptyStateView(systemImage: "exclamationmark.triangle",
                           title: "Couldn’t load", message: message)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .tint(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailScroll(_ detail: MediaDetail) -> some View {
        ZStack {
            if Platform.isMac {
                GeometryReader { proxy in
                    KFImage(detail.backdropURL)
                        .resizable()
                        .fade(duration: 0.3)
                        .placeholder { Theme.surface }
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                        .overlay {
                            ZStack {
                                Color.black.opacity(0.45)
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0.0),
                                        .init(color: .clear, location: 0.35),
                                        .init(color: Theme.background.opacity(0.85), location: 0.75),
                                        .init(color: Theme.background, location: 1.0),
                                    ],
                                    startPoint: .top, endPoint: .bottom)
                            }
                        }
                }
                .ignoresSafeArea()
            }
            detailScrollContent(detail)
        }
    }

    private func detailScrollContent(_ detail: MediaDetail) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                BannerHeader(detail: detail, fallbackTitle: fallbackTitle)

                actions(for: detail)
                metadata(for: detail)
                if let synopsis = detail.description, !synopsis.isEmpty {
                    Section("Synopsis") { Text(synopsis).font(.callout) }
                }
                if !model.castMembers.isEmpty || !detail.cast.isEmpty {
                    CastRow(members: model.castMembers, names: detail.cast)
                }
                crew(for: detail)
                if detail.type == .series, !detail.seasons.isEmpty {
                    EpisodeSection(
                        detail: detail,
                        selectedSeason: Binding(
                            get: { model.selectedSeason },
                            set: { model.selectedSeason = $0 }),
                        watchedEpisodes: progressStore.watchedEpisodes(for: mediaID),
                        onWatch: { watch(episode: $0) },
                        onDownload: { requestDownload(episode: $0) },
                        onSetWatched: { setWatched($1, episode: $0, detail: detail) }
                    )
                }
                moreLikeThis
            }
            .padding(.bottom, 40)
        }
    }

    private func actions(for detail: MediaDetail) -> some View {
        let watchFraction = watchProgressFraction(for: detail)
        let labelHeight: CGFloat = 32
        return HStack(spacing: 12) {
            Button {
                watch(episode: resumeEpisode(for: detail))
            } label: {
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                        ViewThatFits(in: .horizontal) {
                            Text(resumeLabel(for: detail) ?? "Watch")
                                .lineLimit(1)
                            Text(resumeLabel(for: detail, compact: true) ?? "Watch")
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        if isWatchTargetDownloaded(for: detail) {
                            Image(systemName: "arrow.down.circle.fill").font(.caption)
                        }
                    }
                    if let watchFraction {
                        WatchProgressBar(fraction: watchFraction)
                            .frame(maxWidth: .infinity)
                            .frame(height: 3)
                            .padding(.horizontal, 4)
                    }
                }
                .fontWeight(.semibold)
                .foregroundStyle(Theme.onAccent)
                .frame(maxWidth: .infinity, minHeight: labelHeight)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)

            Button {
                requestDownload(episode: firstEpisode(of: detail))
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
                    .lineLimit(1)
                    .fixedSize()
                    .frame(minHeight: labelHeight)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(.white)

            Button {
                watchlist.toggle(id: mediaID, mediaType: type,
                                 title: detail.name.isEmpty ? fallbackTitle : detail.name,
                                 posterURL: detail.posterURL)
            } label: {
                Image(systemName: isInWatchlist ? "bookmark.fill" : "bookmark")
                    .frame(minHeight: labelHeight)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .tint(isInWatchlist ? Theme.accent : .white)
        }
        .controlSize(.large)
        .frame(maxWidth: Platform.isMac ? 480 : .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .disabled(streamer.isPreparing || isAutoResolving)
    }

    private var isInWatchlist: Bool { watchlist.contains(mediaID) }

    private func firstEpisode(of detail: MediaDetail) -> Episode? {
        guard detail.type == .series else { return nil }
        return detail.episodes(inSeason: model.selectedSeason).first
    }

    // MARK: - Watch / Download

    private func watch(episode: Episode?) {
        resumeAt = startPosition(for: episode)
        if let download = downloads.completedDownload(mediaID: mediaID, episodeLabel: episode?.label) {
            playOffline(download, episode: episode)
        } else {
            watchByStreaming(episode: episode)
        }
    }

    private func watchByStreaming(episode: Episode?) {
        guard settings.autoSelectSource else {
            model.requestReleases(intent: .watch, episode: episode)
            return
        }
        Task {
            isAutoResolving = true
            let ranked = await model.rankedStreams(for: episode)
            isAutoResolving = false
            if let stream = ranked.first {
                startWatch(stream: stream, episode: episode,
                           fallbacks: Array(ranked.dropFirst().filter { !$0.isDebrid }))
            } else { model.requestReleases(intent: .watch, episode: episode) }
        }
    }

    private func playOffline(_ download: Download, episode: Episode?) {
        Task {
            guard let url = await downloads.localFileURL(for: download) else {
                watchByStreaming(episode: episode)
                return
            }
            let detail = model.detail
            let name = detail?.name ?? fallbackTitle
            let label = [name, episode?.label].compactMap { $0 }.joined(separator: " · ")
            let startAt = resumeAt
            resumeAt = .zero
            let subtitleContext = SubtitleContext(
                imdbID: mediaID, type: type,
                season: episode?.season, episode: episode?.episode)
            let progressContext = WatchProgressContext(
                mediaID: mediaID, mediaType: type, title: name, posterURL: detail?.posterURL,
                season: episode?.season, episode: episode?.episode, episodeID: episode?.id)
            streamer.playLocalFile(at: url, title: label, subtitleContext: subtitleContext,
                                   startAt: startAt, progress: progressContext,
                                   originalAudioLanguage: model.originalLanguage)
        }
    }

    private func isWatchTargetDownloaded(for detail: MediaDetail) -> Bool {
        downloads.isDownloaded(mediaID: mediaID,
                               episodeLabel: resumeEpisode(for: detail)?.label)
    }

    private func requestDownload(episode: Episode?) {
        guard settings.autoSelectSource else {
            model.requestReleases(intent: .download, episode: episode)
            return
        }
        Task {
            isAutoResolving = true
            let stream = await model.bestStream(for: episode)
            isAutoResolving = false
            if let stream { download(stream: stream, episode: episode) }
            else { model.requestReleases(intent: .download, episode: episode) }
        }
    }

    private func handle(request: MediaDetailModel.ReleaseRequest, stream: TorrentStream) {
        let fallbacks = Array(model.releases
            .filter { $0.id != stream.id && !$0.isDebrid }
            .prefix(3))
        model.dismissReleases()
        switch request.intent {
        case .watch:
            pendingPlay = { startWatch(stream: stream, episode: request.episode, fallbacks: fallbacks) }
        case .download:
            download(stream: stream, episode: request.episode)
        }
    }

    private func startWatch(stream: TorrentStream, episode: Episode?,
                            fallbacks: [TorrentStream] = []) {
        let detail = model.detail
        let name = detail?.name ?? fallbackTitle
        let label = [name, episode?.label].compactMap { $0 }.joined(separator: " · ")
        let backdrop = detail?.backdropURL ?? detail?.posterURL
        let logo = detail?.logoURL
        let subtitleContext = SubtitleContext(
            imdbID: mediaID, type: type,
            season: episode?.season, episode: episode?.episode)

        let playlist: EpisodePlaylist? = {
            guard let episode, let detail, !detail.episodes.isEmpty else { return nil }
            return makeEpisodePlaylist(current: episode, detail: detail)
        }()

        let startAt = resumeAt
        resumeAt = .zero
        let progressContext = WatchProgressContext(
            mediaID: mediaID, mediaType: type, title: name,
            posterURL: detail?.posterURL,
            season: episode?.season, episode: episode?.episode, episodeID: episode?.id)

        if stream.isDebrid, let url = stream.url {
            streamer.playDebrid(url: url, title: label, backdropURL: backdrop, logoURL: logo,
                                subtitleContext: subtitleContext, episodes: playlist,
                                startAt: startAt, progress: progressContext,
                                originalAudioLanguage: model.originalLanguage)
        } else {
            streamer.play(stream, title: label, backdropURL: backdrop, logoURL: logo,
                          subtitleContext: subtitleContext, episodes: playlist,
                          startAt: startAt, resumeFraction: resumeFraction(for: episode),
                          progress: progressContext,
                          originalAudioLanguage: model.originalLanguage,
                          fallbacks: fallbacks)
        }
    }

    // MARK: - Resume ("Continue Watching")

    private var savedProgress: WatchProgress? { progressStore.progress(for: mediaID) }

    private func resumeEpisode(for detail: MediaDetail) -> Episode? {
        guard detail.type != .movie else { return nil }
        let watched = progressStore.watchedEpisodes(for: mediaID)
        guard let saved = savedProgress, let epID = saved.episodeID,
              let idx = detail.episodes.firstIndex(where: { $0.id == epID })
        else {
            guard !watched.isEmpty else { return firstEpisode(of: detail) }
            return detail.episodes.first { !watched.contains($0.label) } ?? firstEpisode(of: detail)
        }
        if saved.isFinished {
            let following = detail.episodes[(idx + 1)...]
            if let next = following.first(where: { !watched.contains($0.label) }) { return next }
            return following.first ?? detail.episodes[idx]
        }
        return detail.episodes[idx]
    }

    private func setWatched(_ watched: Bool, episode: Episode, detail: MediaDetail) {
        progressStore.setWatched(watched, episode: episode, mediaID: mediaID, mediaType: type,
                                 title: detail.name.isEmpty ? fallbackTitle : detail.name,
                                 posterURL: detail.posterURL)
    }

    private func resumeLabel(for detail: MediaDetail, compact: Bool = false) -> String? {
        if detail.type == .movie {
            guard let saved = savedProgress, !saved.isFinished else { return nil }
            return "Resume"
        }
        guard let ep = resumeEpisode(for: detail) else { return nil }
        let code = "S\(ep.season)E\(ep.episode)"
        if compact { return code }
        let resuming = savedProgress.map { !$0.isFinished && $0.episodeID == ep.id } ?? false
        return resuming ? "Resume \(code)" : "Watch \(code)"
    }

    private func watchProgressFraction(for detail: MediaDetail) -> Double? {
        guard let saved = savedProgress, !saved.isFinished, saved.fraction > 0 else { return nil }
        if detail.type == .movie { return min(saved.fraction, 1) }
        guard let ep = resumeEpisode(for: detail), saved.episodeID == ep.id else { return nil }
        return min(saved.fraction, 1)
    }

    private func startPosition(for episode: Episode?) -> Duration {
        guard let saved = savedProgress, !saved.isFinished else { return .zero }
        if type == .movie { return .seconds(saved.positionSeconds) }
        guard let episode, saved.episodeID == episode.id else { return .zero }
        return .seconds(saved.positionSeconds)
    }

    private func resumeFraction(for episode: Episode?) -> Double? {
        guard let saved = savedProgress, !saved.isFinished, saved.fraction > 0 else { return nil }
        if type == .movie { return saved.fraction }
        guard let episode, saved.episodeID == episode.id else { return nil }
        return saved.fraction
    }

    private func download(stream: TorrentStream, episode: Episode?) {
        let detail = model.detail
        downloads.add(
            stream: stream,
            title: detail?.name ?? fallbackTitle,
            mediaID: mediaID,
            mediaType: type,
            posterURL: detail?.posterURL,
            episode: episode)
    }

    private func makeEpisodePlaylist(current: Episode, detail: MediaDetail) -> EpisodePlaylist {
        EpisodePlaylist(current: current, all: detail.episodes) { episode in
            playEpisode(episode)
        }
    }

    private func playEpisode(_ episode: Episode) {
        Task {
            let ranked = await model.rankedStreams(for: episode)
            if let stream = ranked.first {
                startWatch(stream: stream, episode: episode,
                           fallbacks: Array(ranked.dropFirst().filter { !$0.isDebrid }))
            }
        }
    }

    private func metadata(for detail: MediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let rating = detail.imdbRating {
                        Chip(text: String(format: "%.1f", rating), systemImage: "star.fill", tint: .yellow)
                    }
                    if let runtime = detail.runtime {
                        Chip(text: runtime, systemImage: "clock")
                    }
                    if let trailer = detail.trailerURL {
                        Button { openURL(trailer) } label: {
                            Chip(text: "Trailer", systemImage: "play.rectangle.fill", tint: Theme.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play trailer on YouTube")
                    }
                    ForEach(detail.genres, id: \.self) { genre in
                        Chip(text: genre)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private var moreLikeThis: some View {
        #if os(iOS)
        if !model.similar.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("More Like This")
                    .font(.headline)
                    .padding(.horizontal, 20)
                HorizontalShelfScroller {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(model.similar) { item in
                            PosterLink(item: item) {
                                PosterCard(item: item).frame(width: PosterMetrics.shelfWidth(sizeClass))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        #endif
    }

    private func crew(for detail: MediaDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !detail.directors.isEmpty {
                CreditLine(label: detail.directors.count > 1 ? "Directors" : "Director",
                           value: detail.directors.joined(separator: ", "))
            }
            if !detail.writers.isEmpty {
                CreditLine(label: detail.writers.count > 1 ? "Writers" : "Writer",
                           value: detail.writers.joined(separator: ", "))
            }
            if let country = detail.country, !country.isEmpty {
                CreditLine(label: "Country", value: country)
            }
            if let awards = detail.awards, !awards.isEmpty {
                CreditLine(label: "Awards", value: awards)
            }
        }
        .padding(.horizontal, 20)
    }

    @ViewBuilder
    private func Section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }
}

private struct BannerHeader: View {
    let detail: MediaDetail?
    let fallbackTitle: String

    private let height: CGFloat = Platform.isMac ? 460 : 420

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if !Platform.isMac {
            GeometryReader { proxy in
                let offset = proxy.frame(in: .global).minY
                let stretch = max(0, offset)

                KFImage(detail?.backdropURL)
                    .resizable()
                    .fade(duration: 0.2)
                    .placeholder { Theme.surface }
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: height + stretch)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            stops: [
                                .init(color: .black.opacity(0.55), location: 0.0),
                                .init(color: .clear, location: 0.28),
                                .init(color: Theme.background.opacity(0.7), location: 0.68),
                                .init(color: Theme.background, location: 1.0),
                            ],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                    .offset(y: -stretch)
            }
            .frame(height: height)
            }

            titleTreatment
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
        }
        .frame(height: height, alignment: .bottomLeading)
    }

    private var titleTreatment: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let logoURL = detail?.logoURL {
                KFImage(logoURL)
                    .resizable()
                    .placeholder { titleText }
                    .scaledToFit()
                    .frame(maxWidth: Platform.isMac ? 360 : 260, maxHeight: Platform.isMac ? 130 : 90, alignment: .leading)
            } else {
                titleText
            }

            if let summary = detail?.summaryLine, !summary.isEmpty {
                Text(summary)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var titleText: some View {
        Text(detail?.name ?? fallbackTitle)
            .font(.largeTitle.weight(.bold))
            .foregroundStyle(.white)
            .lineLimit(3)
            .minimumScaleFactor(0.7)
    }
}

private struct CastRow: View {
    let members: [CastMember]
    let names: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Cast")
                .font(.headline)
                .padding(.horizontal, 20)

            HorizontalShelfScroller {
                LazyHStack(alignment: .top, spacing: 12) {
                    if members.isEmpty {
                        ForEach(names, id: \.self) { name in
                            personTile(name: name, role: nil, photo: nil)
                        }
                    } else {
                        ForEach(members) { member in
                            NavigationLink(value: member) {
                                personTile(name: member.name, role: member.role, photo: member.photoURL)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private func personTile(name: String, role: String?, photo: URL?) -> some View {
        VStack(spacing: 8) {
            Circle()
                .fill(Theme.surface)
                .frame(width: 64, height: 64)
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
                .font(.caption2)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 80)
        }
    }

    private func initialsLabel(_ name: String) -> some View {
        Text(Self.initials(name))
            .font(.headline)
            .foregroundStyle(.white.opacity(0.7))
    }

    private static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()
    }
}

private struct CreditLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .frame(width: 78, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
