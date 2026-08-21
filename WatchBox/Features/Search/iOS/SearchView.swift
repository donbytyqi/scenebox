//
//  SearchView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI

struct SearchView: View {
    var body: some View {
        NavigationStack {
            SearchScreen()
                .mediaNavigationDestinations()
                .navigationDestination(for: CatalogDestination.self) { dest in
                    CatalogListView(type: dest.type, feed: dest.feed)
                }
        }
    }
}

struct SearchScreen: View {
    @State private var model = SearchModel()
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            if Platform.isMac {
                VStack(spacing: 0) {
                    macSearchHeader
                    SearchResults(model: model)
                }
                .toolbar(.hidden, for: .navigationBar)
            } else {
                SearchResults(model: model)
                    .navigationTitle("Search")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        if !model.isSearching {
                            ToolbarItem(placement: .topBarTrailing) { filterMenu }
                        }
                    }
                    .searchable(text: $model.query,
                                prompt: "Search movies, shows & anime")
            }
        }
            .background(Theme.background)
            .onChange(of: model.query) { _, _ in model.run() }
            .onSubmit(of: .search) { model.run(immediate: true) }
            .task { if model.results.isEmpty { model.run() } }
            .onChange(of: settings.streamSourceBases) { _, _ in
                model.applySettings(settings)
                model.run()
            }
    }

    // MARK: - Mac header

    @FocusState private var macFieldFocused: Bool

    private var macSearchHeader: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search movies, shows & anime", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($macFieldFocused)
                    .onSubmit { model.run(immediate: true) }
                if !model.query.isEmpty {
                    Button { model.query = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .frame(maxWidth: 520)

            if !model.isSearching { filterMenu }
            Spacer(minLength: 0)
            if model.isLoading { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
        .onAppear { macFieldFocused = true }
    }

    // MARK: - Filters

    private var filterMenu: some View {
        Menu {
            if filtersActive {
                Button { resetFilters() } label: {
                    Label("Reset Filters", systemImage: "arrow.counterclockwise")
                }
            }

            Picker("Type", selection: $model.scope) {
                ForEach(SearchModel.Scope.browseScopes) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            Picker("Feed", selection: $model.feed) {
                ForEach(CatalogFeed.allCases) { feed in
                    Text(feed.title).tag(feed)
                }
            }
            Picker("Genre", selection: $model.genre) {
                Text("All Genres").tag(String?.none)
                ForEach(MediaGenre.shared, id: \.self) { genre in
                    Text(genre).tag(String?.some(genre))
                }
            }
        } label: {
            Label("Filters", systemImage: filtersActive
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .tint(filtersActive ? Theme.accent : .white)
        .onChange(of: model.scope) { _, _ in model.run() }
        .onChange(of: model.feed) { _, _ in model.run() }
        .onChange(of: model.genre) { _, _ in model.run() }
    }

    private var filtersActive: Bool {
        model.feed != .popular || model.genre != nil
    }

    private func resetFilters() {
        model.feed = .popular
        model.genre = nil
        model.run()
    }
}

struct SearchResults: View {
    let model: SearchModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    @ViewBuilder
    var body: some View {
        if model.isLoading && model.results.isEmpty {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.results.isEmpty {
            EmptyStateView(systemImage: "magnifyingglass",
                           title: model.isSearching ? "No results" : "Search",
                           message: model.errorMessage ?? "Search by name, or browse by type, feed and genre.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: PosterMetrics.gridColumns(sizeClass), spacing: 16) {
                ForEach(model.results) { item in
                    PosterLink(item: item) {
                        PosterCard(item: item)
                    }
                    .onAppear { model.loadMoreIfNeeded(after: item) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)

            if model.isLoadingMore {
                ProgressView()
                    .tint(Theme.accent)
                    .padding(.bottom, 24)
            }
        }
        .overlay {
            if model.isLoading {
                ProgressView()
                    .tint(Theme.accent)
                    .controlSize(.large)
                    .padding(22)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.isLoading)
    }
}
#endif
