//
//  WatchProgressStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class WatchProgressStore {
    static let shared = WatchProgressStore()

    private(set) var items: [WatchProgress] = []
    private(set) var hasLoaded = false

    @ObservationIgnored private let minRecordSeconds: Double = 15
    @ObservationIgnored private var backend: WatchProgressBackend

    init(backend: WatchProgressBackend = LocalWatchProgressBackend()) {
        self.backend = backend
        Task { await reload() }
    }

    func use(_ backend: WatchProgressBackend) {
        self.backend = backend
        items = []
        hasLoaded = false
        Task { await reload() }
    }

    private func reload() async {
        let loaded = await backend.load()
        items = loaded.sorted { $0.updatedAt > $1.updatedAt }
        hasLoaded = true
    }

    func refresh() {
        Task {
            let remote = await backend.load()
            var merged = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
            for item in remote where (merged[item.id]?.updatedAt ?? .distantPast) < item.updatedAt {
                merged[item.id] = item
            }
            items = merged.values.sorted { $0.updatedAt > $1.updatedAt }
            hasLoaded = true
        }
    }

    func progress(for mediaID: String) -> WatchProgress? {
        items.first { $0.id == mediaID }
    }

    func record(id: String, mediaType: MediaType, title: String, posterURL: URL?,
                season: Int?, episode: Int?, episodeID: String?,
                position: Duration, duration: Duration?) {
        let pos = position.asSeconds
        guard pos >= minRecordSeconds else { return }

        var item = WatchProgress(
            id: id, mediaType: mediaType, title: title,
            posterURLString: posterURL?.absoluteString,
            season: season, episode: episode, episodeID: episodeID,
            positionSeconds: pos, durationSeconds: duration?.asSeconds ?? 0,
            updatedAt: Date())

        if item.isFinished, item.mediaType == .movie {
            remove(id: id)
            return
        }

        if mediaType != .movie, let previous = progress(for: id) {
            var watched = Set(previous.watchedEpisodes ?? [])
            if previous.isFinished, let label = previous.downloadEpisodeLabel { watched.insert(label) }
            if item.isFinished, let label = item.downloadEpisodeLabel { watched.insert(label) }
            item.watchedEpisodes = watched.sorted()
        } else if item.isFinished, let label = item.downloadEpisodeLabel {
            item.watchedEpisodes = [label]
        }

        items.removeAll { $0.id == id }
        items.insert(item, at: 0)
        Task { [backend] in await backend.upsert(item) }
    }

    func watchedEpisodes(for mediaID: String) -> Set<String> {
        guard let saved = progress(for: mediaID) else { return [] }
        var set = Set(saved.watchedEpisodes ?? [])
        if saved.isFinished, let label = saved.downloadEpisodeLabel { set.insert(label) }
        return set
    }

    func hasWatched(mediaID: String, episode: Episode) -> Bool {
        watchedEpisodes(for: mediaID).contains(episode.label)
    }

    func setWatched(_ watched: Bool, episode: Episode, mediaID: String, mediaType: MediaType,
                    title: String, posterURL: URL?) {
        var item = progress(for: mediaID) ?? WatchProgress(
            id: mediaID, mediaType: mediaType, title: title,
            posterURLString: posterURL?.absoluteString,
            season: nil, episode: nil, episodeID: nil,
            positionSeconds: 0, durationSeconds: 0, updatedAt: Date())
        var set = Set(item.watchedEpisodes ?? [])
        if item.isFinished, let label = item.downloadEpisodeLabel { set.insert(label) }

        if watched {
            set.insert(episode.label)
            item.season = episode.season
            item.episode = episode.episode
            item.episodeID = episode.id
            item.positionSeconds = 1
            item.durationSeconds = 1          // fraction 1 → finished
        } else {
            set.remove(episode.label)
            if item.episodeID == episode.id {
                item.positionSeconds = 0
                item.durationSeconds = 0      // back to "not started"
            }
        }
        item.watchedEpisodes = set.sorted()
        item.updatedAt = Date()

        if set.isEmpty, item.positionSeconds <= 0 {
            remove(id: mediaID)
            return
        }
        items.removeAll { $0.id == mediaID }
        items.insert(item, at: 0)
        Task { [backend] in await backend.upsert(item) }
    }

    func remove(id: String) {
        items.removeAll { $0.id == id }
        Task { [backend] in await backend.remove(id: id) }
    }

    func clear() {
        items.removeAll()
        Task { [backend] in await backend.clear() }
    }
}

extension Duration {
    var asSeconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
