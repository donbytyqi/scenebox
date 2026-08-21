//
//  HomeModel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 05.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class HomeModel {
    struct Shelf: Identifiable {
        let id: String
        let title: String
        let type: MediaType
        let feed: CatalogFeed
        var items: [MediaResult]
    }

    private static let specs: [(title: String, type: MediaType, feed: CatalogFeed)] = [
        ("Popular Movies", .movie, .popular),
        ("Popular TV Shows", .series, .popular),
        ("Popular Anime", .anime, .popular),
        ("New Movies", .movie, .new),
        ("Top Rated Movies", .movie, .featured),
    ]

    private(set) var shelves: [Shelf] = []
    private(set) var featured: MediaResult?
    private(set) var featuredDetail: MediaDetail?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var search: TorrentSearch
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(settings: AppSettings? = nil) {
        let settings = settings ?? .shared
        self.search = TorrentSearch(sourceBases: settings.streamSourceBases)
    }

    func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        load()
    }

    func reload() {
        loaded = true
        load()
    }

    func refresh() async {
        reload()
        await loadTask?.value
    }

    func applySettings(_ settings: AppSettings) {
        search = TorrentSearch(sourceBases: settings.streamSourceBases)
        if loaded { load() }
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        loadTask?.cancel()
        loadTask = Task { [search] in
            let specs = Self.specs
            let rows = await withTaskGroup(of: (Int, [MediaResult]).self) { group in
                for (i, spec) in specs.enumerated() {
                    group.addTask {
                        let items = (try? await search.catalog(type: spec.type, feed: spec.feed)) ?? []
                        return (i, items)
                    }
                }
                var results = [[MediaResult]](repeating: [], count: specs.count)
                for await (i, items) in group { results[i] = items }
                return results
            }
            guard !Task.isCancelled else { return }

            var built: [Shelf] = []
            for (i, spec) in specs.enumerated() where !rows[i].isEmpty {
                built.append(Shelf(id: "\(spec.type.rawValue)-\(spec.feed.rawValue)",
                                   title: spec.title, type: spec.type, feed: spec.feed,
                                   items: rows[i]))
            }
            shelves = built
            errorMessage = built.isEmpty ? "Couldn’t load the catalog." : nil
            isLoading = false

            if let top = built.first?.items.first {
                featured = top
                let detail = try? await search.detail(id: top.id, type: top.type)
                guard !Task.isCancelled else { return }
                featuredDetail = detail
            }
        }
    }
}
