//
//  WatchlistItem.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

import Foundation

nonisolated struct WatchlistItem: Identifiable, Codable, Sendable, Hashable {
    let id: String                 // media IMDb/kitsu id, matches `MediaResult.id`
    let mediaType: MediaType
    var title: String
    var posterURLString: String?
    var addedAt: Date

    var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
}

extension WatchlistItem {
    var mediaResult: MediaResult {
        MediaResult(id: id, type: mediaType, name: title,
                    year: nil, posterURL: posterURL, description: nil)
    }
}

// MARK: - Backend

protocol WatchlistBackend: Sendable {
    func load() async -> [WatchlistItem]
    func upsert(_ item: WatchlistItem) async
    func remove(id: String) async
}

actor LocalWatchlistBackend: WatchlistBackend {
    private let url: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        url = base.appendingPathComponent("watchlist.json")
    }

    func load() async -> [WatchlistItem] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([WatchlistItem].self, from: data)
        else { return [] }
        return items
    }

    func upsert(_ item: WatchlistItem) async {
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

    private func write(_ items: [WatchlistItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
