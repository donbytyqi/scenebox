//
//  HomeView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI

struct HomeView: View {
    @State private var model = HomeModel()
    @State private var search = SearchModel()
    @Environment(AppSettings.self) private var settings
    @Environment(WatchProgressStore.self) private var progress
    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        NavigationStack {
            Group {
                if search.isSearching {
                    SearchResults(model: search)
                } else if (model.isLoading && model.shelves.isEmpty) || !progress.hasLoaded {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = model.errorMessage, model.shelves.isEmpty {
                    EmptyStateView(systemImage: "exclamationmark.triangle", title: "Couldn’t load",
                                   message: message, actionTitle: "Retry") { model.reload() }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: Platform.isMac ? 32 : 22) {
                            if !progress.items.isEmpty {
                                ContinueWatchingShelf(items: progress.items)
                            }
                            if !unwatchedWatchlist.isEmpty {
                                WatchlistShelfRow(items: unwatchedWatchlist)
                            }
                            ForEach(model.shelves) { shelf in
                                HomeShelfRow(shelf: shelf)
                            }
                        }
                        .padding(.vertical, 12)
                    }
                    .refreshable {
                        progress.refresh()
                        async let catalog: () = model.refresh()
                        async let saved: () = watchlist.refresh()
                        _ = await (catalog, saved)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(Platform.isMac ? "" : "Home")
            .toolbar {
                if search.isSearching, search.isLoading {
                    ToolbarItem(placement: .topBarTrailing) { ProgressView() }
                }
            }
            .toolbar(Platform.isMac ? .hidden : .automatic, for: .navigationBar)
            .modifier(HomeSearchField(query: $search.query))
            .onChange(of: search.query) { _, query in
                if query.trimmingCharacters(in: .whitespaces).isEmpty { return }
                search.run()
            }
            .onSubmit(of: .search) { search.run(immediate: true) }
            .mediaNavigationDestinations()
            .navigationDestination(for: CatalogDestination.self) { dest in
                CatalogListView(type: dest.type, feed: dest.feed)
            }
        }
        .task { model.loadIfNeeded() }
        .onAppear { progress.refresh() }
        .onChange(of: settings.streamSourceBases) { _, _ in
            model.applySettings(settings)
            search.applySettings(settings)
        }
    }

    private var unwatchedWatchlist: [MediaResult] {
        watchlist.items
            .filter { progress.progress(for: $0.id) == nil }
            .map(\.mediaResult)
    }
}

private struct WatchlistShelfRow: View {
    let items: [MediaResult]
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: Platform.isMac ? 14 : 10) {
            Text("Your Watchlist")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)

            HorizontalShelfScroller {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        PosterLink(item: item) {
                            PosterCard(item: item).frame(width: PosterMetrics.shelfWidth(sizeClass))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct HomeShelfRow: View {
    let shelf: HomeModel.Shelf
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        VStack(alignment: .leading, spacing: Platform.isMac ? 14 : 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(shelf.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                NavigationLink(value: CatalogDestination(type: shelf.type, feed: shelf.feed)) {
                    HStack(spacing: 2) {
                        Text("See all")
                        Image(systemName: "chevron.right").font(.caption2.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 16)

            HorizontalShelfScroller {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(shelf.items) { item in
                        PosterLink(item: item) {
                            PosterCard(item: item).frame(width: PosterMetrics.shelfWidth(sizeClass))
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}

private struct HomeSearchField: ViewModifier {
    @Binding var query: String

    func body(content: Content) -> some View {
        if Platform.isMac {
            content
        } else {
            content.searchable(text: $query, prompt: "Search movies, shows & anime")
        }
    }
}
#endif
