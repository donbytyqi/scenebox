//
//  TVHomeView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(tvOS)
import SwiftUI

struct TVHomeView: View {
    @State private var model = HomeModel()
    @Environment(AppSettings.self) private var settings
    @Environment(WatchProgressStore.self) private var progress
    @Environment(WatchlistStore.self) private var watchlist

    static let edge: CGFloat = 80

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if (model.isLoading && model.shelves.isEmpty) || !progress.hasLoaded {
                    ProgressView().tint(.white).controlSize(.large)
                } else if let message = model.errorMessage, model.shelves.isEmpty {
                    EmptyStateView(systemImage: "exclamationmark.triangle",
                                   title: "Couldn’t load", message: message)
                } else {
                    shelves
                }
            }
            .mediaNavigationDestinations()
            .navigationDestination(for: CatalogDestination.self) { dest in
                TVCatalogView(type: dest.type, feed: dest.feed)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { model.loadIfNeeded() }
        .onAppear { progress.refresh() }
        .onChange(of: settings.streamSourceBases) { _, _ in model.applySettings(settings) }
    }

    private var shelves: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if let featured = model.featured {
                    TVSpotlight(item: featured, detail: model.featuredDetail)
                }
                if !progress.items.isEmpty {
                    TVContinueWatchingShelf(items: progress.items)
                }
                if !unwatchedWatchlist.isEmpty {
                    TVPosterShelf(title: "Your Watchlist", items: unwatchedWatchlist)
                }
                ForEach(model.shelves) { shelf in
                    TVPosterShelf(title: shelf.title, items: shelf.items,
                                  destination: CatalogDestination(type: shelf.type, feed: shelf.feed))
                }
            }
            .padding(.bottom, 60)
        }
    }

    private var unwatchedWatchlist: [MediaResult] {
        watchlist.items
            .filter { progress.progress(for: $0.id) == nil }
            .map(\.mediaResult)
    }
}

private struct TVSpotlight: View {
    let item: MediaResult
    let detail: MediaDetail?

    private var backdropURL: URL? { detail?.backdropURL ?? item.posterURL }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TVBackdropImage(url: backdropURL)

            LinearGradient(colors: [.black.opacity(0.85), .black.opacity(0.2), .clear],
                           startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [
                .init(color: .clear, location: 0.4),
                .init(color: Theme.background.opacity(0.6), location: 0.85),
                .init(color: Theme.background, location: 1.0),
            ], startPoint: .top, endPoint: .bottom)

            content
                .padding(.horizontal, TVHomeView.edge)
                .padding(.bottom, 44)
        }
        .frame(height: 660)
        .frame(maxWidth: .infinity)
        .clipped()
        .focusSection()
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            TVTitleArt(logoURL: detail?.logoURL, title: item.name,
                       maxLogoWidth: 620, maxLogoHeight: 200, titleSize: 62)

            Text(metaLine)
                .font(.title3)
                .foregroundStyle(.white.opacity(0.7))

            if let overview = detail?.description ?? item.description, !overview.isEmpty {
                Text(overview)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(3)
                    .lineSpacing(4)
                    .frame(maxWidth: 820, alignment: .leading)
            }

            NavigationLink(value: item) {
                Label("View Details", systemImage: "info.circle")
            }
            .buttonStyle(TVAccentButtonStyle())
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var metaLine: String {
        var parts: [String] = []
        if let year = detail?.year ?? item.year { parts.append(year) }
        if let runtime = detail?.runtime { parts.append(runtime) }
        let genres = detail?.genres.prefix(3).joined(separator: " · ")
        if let genres, !genres.isEmpty { parts.append(genres) }
        return parts.joined(separator: "  ·  ")
    }
}
#endif
