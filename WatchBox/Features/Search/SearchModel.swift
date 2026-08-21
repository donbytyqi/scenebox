//
//  SearchModel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class SearchModel {
    enum Scope: String, CaseIterable, Identifiable {
        case all, movie, series, anime
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: "All"
            case .movie: "Movies"
            case .series: "TV Shows"
            case .anime: "Anime"
            }
        }
        var types: [MediaType] {
            switch self {
            case .all: [.movie, .series, .anime]
            case .movie: [.movie]
            case .series: [.series]
            case .anime: [.anime]
            }
        }

        static let browseScopes: [Scope] = [.movie, .series, .anime]
    }

    var query = ""
    var scope: Scope = .movie
    var feed: CatalogFeed = .popular
    var genre: String?

    private(set) var results: [MediaResult] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var search: TorrentSearch
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var moreTask: Task<Void, Never>?
    @ObservationIgnored private var pageOffsets: [MediaType: Int] = [:]
    @ObservationIgnored private var exhausted: Set<MediaType> = []
    @ObservationIgnored private var rowsByType: [MediaType: [MediaResult]] = [:]
    @ObservationIgnored private var activeTypes: [MediaType] = []
    @ObservationIgnored private var activeQuery = ""
    @ObservationIgnored private var generation = 0

    var isSearching: Bool { !query.trimmingCharacters(in: .whitespaces).isEmpty }

    init(settings: AppSettings? = nil) {
        let settings = settings ?? .shared
        self.search = TorrentSearch(sourceBases: settings.streamSourceBases)
    }

    func applySettings(_ settings: AppSettings) {
        search = TorrentSearch(sourceBases: settings.streamSourceBases)
    }

    func run(immediate: Bool = false) {
        task?.cancel()
        moreTask?.cancel()
        isLoadingMore = false
        generation &+= 1
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let searching = !trimmed.isEmpty
        let types = searching ? [.movie, .series, .anime] : scope.types
        activeTypes = types
        activeQuery = trimmed
        pageOffsets = [:]
        exhausted = []
        rowsByType = [:]
        isLoading = true

        task = Task { [search, feed, genre] in
            if searching, !immediate {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            isLoading = true

            var rows = [[MediaResult]](repeating: [], count: types.count)
            await withTaskGroup(of: (Int, [MediaResult]).self) { group in
                for (i, type) in types.enumerated() {
                    group.addTask {
                        let items: [MediaResult]
                        if searching {
                            items = (try? await search.search(trimmed, type: type)) ?? []
                        } else {
                            items = (try? await search.catalog(type: type, feed: feed, genre: genre)) ?? []
                        }
                        return (i, items)
                    }
                }
                for await (i, items) in group {
                    guard !Task.isCancelled else { return }
                    rows[i] = items
                    let partial = searching ? Self.rankedBySearchRelevance(rows, query: trimmed)
                                            : (rows.first ?? [])
                    if !partial.isEmpty { results = partial }
                }
            }
            guard !Task.isCancelled else { return }

            for (i, type) in types.enumerated() {
                rowsByType[type] = rows[i]
                pageOffsets[type] = rows[i].count
                if rows[i].isEmpty { exhausted.insert(type) }
            }
            results = searching ? Self.rankedBySearchRelevance(rows, query: trimmed)
                                 : (rows.first ?? [])
            errorMessage = results.isEmpty
                ? (searching ? "Nothing matched your search." : "Nothing to show here.")
                : nil
            isLoading = false
        }
    }

    // MARK: - Paging

    var canLoadMore: Bool {
        !isLoading && !results.isEmpty && activeTypes.contains { !exhausted.contains($0) }
    }

    func loadMoreIfNeeded(after item: MediaResult) {
        guard canLoadMore, !isLoadingMore,
              let index = results.firstIndex(where: { $0.id == item.id }),
              index >= results.count - 12 else { return }
        isLoadingMore = true
        let searching = !activeQuery.isEmpty
        let types = activeTypes.filter { !exhausted.contains($0) }
        let offsets = pageOffsets
        let query = activeQuery
        let gen = generation

        moreTask = Task { [search, feed, genre] in
            var pages: [MediaType: [MediaResult]] = [:]
            await withTaskGroup(of: (MediaType, [MediaResult]).self) { group in
                for type in types {
                    let skip = offsets[type] ?? 0
                    group.addTask {
                        let items: [MediaResult]
                        if searching {
                            items = (try? await search.search(query, type: type, skip: skip)) ?? []
                        } else {
                            items = (try? await search.catalog(type: type, feed: feed, genre: genre, skip: skip)) ?? []
                        }
                        return (type, items)
                    }
                }
                for await (type, items) in group { pages[type] = items }
            }
            guard !Task.isCancelled, gen == generation else { return }

            let known = Set(results.map(\.id))
            var freshRows: [[MediaResult]] = []
            for type in types {
                let page = pages[type] ?? []
                let fresh = page.filter { !known.contains($0.id) }
                if fresh.isEmpty { exhausted.insert(type); continue }
                pageOffsets[type, default: 0] += page.count
                rowsByType[type, default: []] += fresh
                freshRows.append(fresh)
            }
            let appended = searching ? Self.rankedBySearchRelevance(freshRows, query: query)
                                     : freshRows.flatMap { $0 }
            results += appended
            isLoadingMore = false
        }
    }

    // MARK: - Search ranking

    private static func rankedBySearchRelevance(_ rows: [[MediaResult]], query: String) -> [MediaResult] {
        let q = query.lowercased()
        var seen = Set<String>()
        var scored: [(result: MediaResult, tier: Int, rank: Int)] = []

        for typeResults in rows {
            for (rank, result) in typeResults.enumerated() where seen.insert(result.id).inserted {
                scored.append((result, matchTier(of: result.name, query: q), rank))
            }
        }

        return scored
            .sorted { a, b in
                if a.tier != b.tier { return a.tier > b.tier }
                return a.rank < b.rank
            }
            .map(\.result)
    }

    private static func matchTier(of name: String, query q: String) -> Int {
        let name = name.lowercased()
        if name == q { return 4 }
        if name.hasPrefix(q) { return 3 }
        if name.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 2 }
        if name.contains(q) { return 1 }
        return 0
    }
}
