//
//  TraktSync.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class TraktSync {
    static let shared = TraktSync()

    private(set) var isBackfilling = false

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var plays: Set<String>

    private static let playsKey = "traktSyncedPlays"

    init(settings: AppSettings = .shared) {
        self.settings = settings
        plays = Set(UserDefaults.standard.stringArray(forKey: Self.playsKey) ?? [])
    }

    private var active: Bool { settings.traktSyncEnabled && settings.traktConnected }

    // Kitsu ids have no IMDb id and can't be represented on Trakt.
    nonisolated static func canSync(_ id: String) -> Bool { id.hasPrefix("tt") }

    // MARK: - Live events

    func playbackFinished(id: String, mediaType: MediaType, season: Int?, episode: Int?) {
        guard active, Self.canSync(id) else { return }
        let key = playKey(id: id, season: season, episode: episode)
        guard !plays.contains(key) else { return }
        rememberPlays([key])
        let item = TraktHistoryItem(imdbID: id, season: season, episode: episode, watchedAt: Date())
        push { client, token in
            try await client.addToHistory([item], accessToken: token)
        }
    }

    func episodeSetWatched(_ watched: Bool, id: String, season: Int, episode: Int) {
        guard active, Self.canSync(id) else { return }
        let key = playKey(id: id, season: season, episode: episode)
        let item = TraktHistoryItem(imdbID: id, season: season, episode: episode,
                                    watchedAt: watched ? Date() : nil)
        if watched {
            guard !plays.contains(key) else { return }
            rememberPlays([key])
            push { client, token in
                try await client.addToHistory([item], accessToken: token)
            }
        } else {
            forgetPlay(key)
            push { client, token in
                try await client.removeFromHistory([item], accessToken: token)
            }
        }
    }

    func watchlistChanged(added: Bool, id: String, mediaType: MediaType) {
        guard active, Self.canSync(id) else { return }
        let movieIDs = mediaType == .movie ? [id] : []
        let showIDs = mediaType == .movie ? [] : [id]
        push { client, token in
            if added {
                try await client.addToWatchlist(movieIDs: movieIDs, showIDs: showIDs, accessToken: token)
            } else {
                try await client.removeFromWatchlist(movieIDs: movieIDs, showIDs: showIDs, accessToken: token)
            }
        }
    }

    // MARK: - One-time backfill

    func backfillIfNeeded() async {
        guard active, !isBackfilling else { return }
        let username = settings.traktUsername
        guard !username.isEmpty, settings.traktBackfillUsername != username else { return }
        guard let client = TraktClient(),
              let token = await TraktStore.shared.validAccessToken() else { return }

        isBackfilling = true
        defer { isBackfilling = false }

        // A different account than last time starts from a clean slate.
        plays.removeAll()

        let watchlist = WatchlistStore.shared.items.filter { Self.canSync($0.id) }
        let movieIDs = watchlist.filter { $0.mediaType == .movie }.map(\.id)
        let showIDs = watchlist.filter { $0.mediaType != .movie }.map(\.id)

        var history: [TraktHistoryItem] = []
        var keys: [String] = []
        for progress in WatchProgressStore.shared.items where Self.canSync(progress.id) {
            if progress.mediaType == .movie {
                if progress.isFinished {
                    history.append(TraktHistoryItem(imdbID: progress.id, watchedAt: progress.updatedAt))
                    keys.append(playKey(id: progress.id, season: nil, episode: nil))
                }
            } else {
                for label in WatchProgressStore.shared.watchedEpisodes(for: progress.id) {
                    guard let (season, episode) = Self.parseEpisodeLabel(label) else { continue }
                    history.append(TraktHistoryItem(imdbID: progress.id, season: season,
                                                    episode: episode, watchedAt: progress.updatedAt))
                    keys.append(playKey(id: progress.id, season: season, episode: episode))
                }
            }
        }

        do {
            try await client.addToWatchlist(movieIDs: movieIDs, showIDs: showIDs, accessToken: token)
            try await client.addToHistory(history, accessToken: token)
            rememberPlays(keys)
            settings.traktBackfillUsername = username
        } catch {
        }
    }

    // MARK: - Plumbing

    // Labels are stored as "S1E2" (`WatchProgress.downloadEpisodeLabel` / `Episode.label`).
    nonisolated static func parseEpisodeLabel(_ label: String) -> (season: Int, episode: Int)? {
        guard label.hasPrefix("S"), let eIndex = label.firstIndex(of: "E"),
              let season = Int(label[label.index(after: label.startIndex)..<eIndex]),
              let episode = Int(label[label.index(after: eIndex)...]) else { return nil }
        return (season, episode)
    }

    private func playKey(id: String, season: Int?, episode: Int?) -> String {
        guard let season, let episode else { return id }
        return "\(id):\(season):\(episode)"
    }

    private func rememberPlays(_ keys: [String]) {
        plays.formUnion(keys)
        if plays.count > 5000 { plays.removeAll() }
        defaults.set(Array(plays), forKey: Self.playsKey)
    }

    private func forgetPlay(_ key: String) {
        plays.remove(key)
        defaults.set(Array(plays), forKey: Self.playsKey)
    }

    private func push(_ op: @escaping @Sendable (TraktClient, String) async throws -> Void) {
        Task {
            guard let client = TraktClient(),
                  let token = await TraktStore.shared.validAccessToken() else { return }
            try? await op(client, token)
        }
    }
}
