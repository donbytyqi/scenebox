//
//  WatchProgress.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation

nonisolated struct WatchProgress: Identifiable, Codable, Sendable, Hashable {
    let id: String                 // media IMDb id, matches `MediaResult.id`
    let mediaType: MediaType
    var title: String
    var posterURLString: String?

    var season: Int?
    var episode: Int?
    var episodeID: String?

    var positionSeconds: Double
    var durationSeconds: Double
    var updatedAt: Date
    var watchedEpisodes: [String]? = nil

    var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }

    var fraction: Double {
        guard durationSeconds > 0 else { return 0 }
        return min(1, max(0, positionSeconds / durationSeconds))
    }

    var isFinished: Bool { fraction >= 0.92 }

    var episodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season) · E\(episode)"
    }

    func hasWatched(episodeLabel label: String) -> Bool {
        if watchedEpisodes?.contains(label) == true { return true }
        return isFinished && downloadEpisodeLabel == label
    }

    var downloadEpisodeLabel: String? {
        guard let season, let episode else { return nil }
        return "S\(season)E\(episode)"
    }
}

extension WatchProgress {
    var mediaResult: MediaResult {
        MediaResult(id: id, type: mediaType, name: title,
                    year: nil, posterURL: posterURL, description: nil)
    }
}

// MARK: - Backend

protocol WatchProgressBackend: Sendable {
    func load() async -> [WatchProgress]
    func upsert(_ item: WatchProgress) async
    func remove(id: String) async
    func clear() async
}

actor LocalWatchProgressBackend: WatchProgressBackend {
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("continue-watching.json")
    }

    func load() async -> [WatchProgress] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([WatchProgress].self, from: data)
        else { return [] }
        return items
    }

    func upsert(_ item: WatchProgress) async {
        var all = await load()
        all.removeAll { $0.id == item.id }
        all.append(item)
        write(all)
    }

    func remove(id: String) async {
        var all = await load()
        all.removeAll { $0.id == id }
        write(all)
    }

    func clear() async { write([]) }

    private func write(_ items: [WatchProgress]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
