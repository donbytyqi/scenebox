//
//  CatalogListView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI

struct CatalogListView: View {
    let type: MediaType

    @State private var model: CatalogModel
    @State private var searchPresented: Bool
    @Environment(AppSettings.self) private var settings
    @Environment(\.horizontalSizeClass) private var sizeClass

    init(type: MediaType, feed: CatalogFeed, autoFocusSearch: Bool = false) {
        self.type = type
        _model = State(initialValue: CatalogModel(type: type, feed: feed))
        _searchPresented = State(initialValue: autoFocusSearch)
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if Platform.isMac {
                VStack(spacing: 0) {
                    macHeader($model.feed, $model.genre)
                    grid.overlay { statusOverlay }
                }
                .toolbar(.hidden, for: .navigationBar)
            } else {
                grid
                    .overlay { statusOverlay }
                    .navigationTitle(type.browseTitle)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        if !model.isShowingSearchResults {
                            ToolbarItem(placement: .topBarTrailing) { filterMenu($model.feed, $model.genre) }
                        }
                    }
                    .searchable(text: $model.query, isPresented: $searchPresented,
                                prompt: "Search \(type.browseTitle.lowercased())")
            }
        }
            .background(Theme.background)
            .onSubmit(of: .search) { model.runSearch() }
            .onChange(of: model.query) { _, value in
                if value.isEmpty { model.clearSearch() }
            }
            .onChange(of: settings.streamSourceBases) { _, _ in
                model.applySettings(settings)
            }
            .task { model.loadIfNeeded() }
    }

    @Environment(\.dismiss) private var dismiss

    private func macHeader(_ feed: Binding<CatalogFeed>, _ genre: Binding<String?>) -> some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            Text(type.browseTitle)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            filterMenu(feed, genre)
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search \(type.browseTitle.lowercased())", text: $model.query)
                    .textFieldStyle(.plain)
                    .onSubmit { model.runSearch() }
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
            .frame(maxWidth: 380)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func filterMenu(_ feed: Binding<CatalogFeed>, _ genre: Binding<String?>) -> some View {
        Menu {
            Picker("Category", selection: feed) {
                ForEach(CatalogFeed.allCases) { feed in
                    Text(feed.title).tag(feed)
                }
            }
            Picker("Genre", selection: genre) {
                Text("All Genres").tag(String?.none)
                ForEach(MediaGenre.shared, id: \.self) { genre in
                    Text(genre).tag(String?.some(genre))
                }
            }
        } label: {
            let active = model.feed != .popular || model.genre != nil
            Image(systemName: active
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
            .foregroundStyle(active ? Theme.accent : Color.white)
        }
    }

    private var grid: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVGrid(columns: PosterMetrics.gridColumns(sizeClass), spacing: 16) {
                ForEach(model.items) { item in
                    PosterLink(item: item) {
                        PosterCard(item: item)
                    }
                    .onAppear { model.loadMoreIfNeeded(after: item) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)

            if model.isPaging {
                ProgressView().padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if model.isLoading && model.items.isEmpty {
            ProgressView()
        } else if model.items.isEmpty, let message = model.errorMessage {
            if model.isShowingSearchResults {
                EmptyStateView(systemImage: "magnifyingglass", title: "No results", message: message)
            } else {
                EmptyStateView(systemImage: "exclamationmark.triangle",
                               title: "Couldn’t load", message: message,
                               actionTitle: "Retry") { model.reload() }
            }
        }
    }
}
#endif
