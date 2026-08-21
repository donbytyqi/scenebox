//
//  CatalogModel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 05.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class CatalogModel {
    let type: MediaType

    var feed: CatalogFeed = .popular { didSet { reload() } }
    var genre: String? { didSet { reload() } }
    var query = ""

    private(set) var items: [MediaResult] = []
    private(set) var isLoading = false
    private(set) var isPaging = false
    private(set) var errorMessage: String?
    private(set) var isShowingSearchResults = false

    @ObservationIgnored private var search: TorrentSearch
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var reachedEnd = false

    init(type: MediaType, feed: CatalogFeed = .popular, settings: AppSettings? = nil) {
        self.type = type
        self.feed = feed
        let settings = settings ?? .shared
        self.search = TorrentSearch(sourceBases: settings.streamSourceBases)
    }

    deinit {
        loadTask?.cancel()
        searchTask?.cancel()
    }

    // MARK: - Feed

    func loadIfNeeded() {
        guard items.isEmpty, !isLoading else { return }
        reload()
    }

    func reload() {
        guard !isShowingSearchResults else { return }
        loadTask?.cancel()
        reachedEnd = false
        isLoading = true
        errorMessage = nil

        loadTask = Task { [feed, genre, type, search] in
            do {
                let page = try await search.catalog(type: type, feed: feed, genre: genre)
                guard !Task.isCancelled else { return }
                items = page
                errorMessage = page.isEmpty ? "Nothing in this feed right now." : nil
            } catch {
                guard !Task.isCancelled else { return }
                items = []
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    func loadMoreIfNeeded(after item: MediaResult) {
        guard !isShowingSearchResults, !isPaging, !reachedEnd, !isLoading else { return }
        guard let index = items.firstIndex(where: { $0.id == item.id }),
              index >= items.count - 8 else { return }

        isPaging = true
        let skip = items.count
        Task { [feed, genre, type, search] in
            defer { isPaging = false }
            guard let page = try? await search.catalog(type: type, feed: feed, genre: genre, skip: skip),
                  !Task.isCancelled
            else { return }

            guard !page.isEmpty else { reachedEnd = true; return }
            let known = Set(items.map(\.id))
            items.append(contentsOf: page.filter { !known.contains($0.id) })
        }
    }

    // MARK: - Search

    func runSearch(immediate: Bool = false) {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { clearSearch(); return }

        searchTask?.cancel()
        loadTask?.cancel()
        isShowingSearchResults = true
        errorMessage = nil
        if items.isEmpty { isLoading = true }   // spinner only when nothing's shown yet

        searchTask = Task { [type, search, immediate] in
            if !immediate {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            isLoading = true
            let found = (try? await search.search(trimmed, type: type)) ?? []
            guard !Task.isCancelled else { return }
            items = found
            errorMessage = found.isEmpty ? "No \(type == .movie ? "movies" : "shows") match “\(trimmed)”." : nil
            isLoading = false
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        query = ""
        guard isShowingSearchResults else { return }
        isShowingSearchResults = false
        items = []
        reload()
    }

    func applySettings(_ settings: AppSettings) {
        search = TorrentSearch(sourceBases: settings.streamSourceBases)
    }
}
