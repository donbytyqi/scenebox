//
//  MediaDetailModel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation
import Observation
import Kingfisher

@MainActor
@Observable
final class MediaDetailModel {
    let mediaID: String
    let type: MediaType

    private(set) var detail: MediaDetail?
    private(set) var castMembers: [CastMember] = []
    private(set) var originalLanguage: String?
    private(set) var similar: [MediaResult] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var imagesReady = false

    var isReady: Bool { detail != nil && imagesReady }

    var selectedSeason: Int = 1

    var releaseRequest: ReleaseRequest?
    private(set) var releases: [TorrentStream] = []
    private(set) var isLoadingReleases = false
    private(set) var releaseError: String?

    @ObservationIgnored private var search: TorrentSearch
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var releaseTask: Task<Void, Never>?
    @ObservationIgnored private let settings: AppSettings

    init(mediaID: String, type: MediaType, settings: AppSettings? = nil) {
        self.mediaID = mediaID
        self.type = type
        let settings = settings ?? .shared
        self.settings = settings
        self.search = TorrentSearch(sourceBases: settings.streamSourceBases)
    }

    deinit {
        loadTask?.cancel()
        releaseTask?.cancel()
    }

    struct ReleaseRequest: Identifiable, Equatable {
        enum Intent { case watch, download }

        let intent: Intent
        let episode: Episode?

        var id: String { "\(intent)-\(episode?.id ?? "movie")" }

        var title: String {
            switch intent {
            case .watch: "Choose a release to stream"
            case .download: "Choose a release to download"
            }
        }
    }

    // MARK: - Metadata

    func load() {
        guard detail == nil, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        loadTask = Task { [mediaID, type, search] in
            do {
                let fetched = try await search.detail(id: mediaID, type: type)
                guard !Task.isCancelled else { return }
                detail = fetched
                selectedSeason = fetched.seasons.first ?? 1

                await Self.prefetch([fetched.backdropURL, fetched.logoURL])
                guard !Task.isCancelled else { return }
                imagesReady = true

                async let cast: Void = loadCast(for: fetched)
                async let related: Void = loadSimilar(for: fetched)
                _ = await (cast, related)
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func loadCast(for detail: MediaDetail) async {
        guard let tmdbID = detail.moviedbID,
              let tmdb = TMDBClient(key: settings.tmdbAPIKey) else { return }
        async let members = tmdb.cast(tmdbID: tmdbID, type: detail.type)
        async let language = tmdb.originalLanguage(tmdbID: tmdbID, type: detail.type)
        let (cast, code) = await (members, language)
        guard !Task.isCancelled else { return }
        castMembers = cast
        originalLanguage = code
    }

    private func loadSimilar(for detail: MediaDetail) async {
        guard let genre = detail.genres.first, !genre.isEmpty else { return }
        let items = (try? await search.catalog(type: detail.type, feed: .popular, genre: genre)) ?? []
        guard !Task.isCancelled else { return }
        similar = Array(items.filter { $0.id != detail.id }.prefix(20))
    }

    private static func prefetch(_ urls: [URL?]) async {
        let targets = urls.compactMap { $0 }
        guard !targets.isEmpty else { return }
        await withCheckedContinuation { continuation in
            ImagePrefetcher(urls: targets, completionHandler: { _, _, _ in
                continuation.resume()
            }).start()
        }
    }

    // MARK: - Releases

    func requestReleases(intent: ReleaseRequest.Intent, episode: Episode? = nil) {
        releaseRequest = ReleaseRequest(intent: intent, episode: episode)
        loadReleases(for: episode)
    }

    private func loadReleases(for episode: Episode?) {
        releaseTask?.cancel()
        releases = []
        releaseError = nil
        isLoadingReleases = true

        releaseTask = Task { [mediaID, type, search, settings] in
            do {
                let found = try await search.streams(
                    id: mediaID, type: type,
                    season: episode?.season, episode: episode?.episode)
                guard !Task.isCancelled else { return }

                releases = Self.rank(found, preferring: settings.preferredResolution)
                releaseError = releases.isEmpty ? "No sources available for this title." : nil
            } catch {
                guard !Task.isCancelled else { return }
                releaseError = error.localizedDescription
            }
            isLoadingReleases = false
        }
    }

    func dismissReleases() {
        releaseTask?.cancel()
        releaseRequest = nil
        releases = []
        releaseError = nil
        isLoadingReleases = false
    }

    func bestStream(for episode: Episode?) async -> TorrentStream? {
        await rankedStreams(for: episode).first
    }

    func rankedStreams(for episode: Episode?, limit: Int = 4) async -> [TorrentStream] {
        let found = (try? await search.streams(
            id: mediaID, type: type,
            season: episode?.season, episode: episode?.episode)) ?? []
        var remaining = found
        var ranked: [TorrentStream] = []
        while ranked.count < limit,
              let best = StreamPicker.best(from: remaining,
                                           preferredResolution: settings.preferredResolution,
                                           debridEnabled: settings.debridEnabled) {
            ranked.append(best)
            remaining.removeAll { $0.id == best.id }
        }
        return ranked
    }

    private static func rank(_ streams: [TorrentStream], preferring resolution: String) -> [TorrentStream] {
        var seen = Set<String>()
        let unique = streams.filter { seen.insert($0.id).inserted }
        let wanted = resolution.lowercased()
        guard !wanted.isEmpty else { return unique }
        let preferred = unique.filter { $0.resolution?.lowercased() == wanted }
        let rest = unique.filter { $0.resolution?.lowercased() != wanted }
        return preferred + rest
    }
}
