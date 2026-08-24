//
//  TraktLibraryView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import SwiftUI

struct TraktLibrarySection: View {
    @Environment(AppSettings.self) private var settings
    @State private var trakt = TraktStore.shared
    #if os(tvOS)
    @State private var showConnect = false
    #endif

    var body: some View {
        Group {
            if settings.traktConnected {
                TraktListsList(trakt: trakt)
            } else {
                notConnected
            }
        }
        .navigationDestination(for: TraktListSummary.self) { list in
            TraktListItemsView(list: list)
        }
        .alert("Sync library to Trakt?", isPresented: Binding(
            get: { trakt.pendingBackfillOffer },
            set: { if !$0 { trakt.pendingBackfillOffer = false } })) {
            Button("Sync") {
                settings.traktSyncEnabled = true
                Task { await TraktSync.shared.backfillIfNeeded() }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Your watchlist and watched history will be sent to your Trakt account and kept in sync. Anime from Kitsu can't be synced because it has no IMDb id.")
        }
        #if os(tvOS)
        .sheet(isPresented: $showConnect) {
            TraktConnectSheet()
                .environment(settings)
        }
        #endif
    }

    private var notConnected: some View {
        VStack(spacing: 20) {
            EmptyStateView(
                systemImage: "list.and.film",
                title: "Trakt not connected",
                message: trakt.isConfigured
                    ? "Sign in with your Trakt account to browse your watchlist, favorites and lists here."
                    : "Trakt isn't available in this build.")
            if trakt.isConfigured {
                if trakt.isAuthorizing {
                    ProgressView()
                } else {
                    #if os(tvOS)
                    Button("Connect Trakt") { showConnect = true }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.onAccent)
                    #else
                    Button("Connect Trakt") { trakt.signIn() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.onAccent)
                    #endif
                }
                if let error = trakt.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(tvOS)
        .frame(minHeight: 500)   // hosted in a ScrollView: give it room
        #endif
    }
}

private struct TraktListsList: View {
    let trakt: TraktStore

    var body: some View {
        Group {
            if trakt.lists.isEmpty, trakt.isLoadingLists {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if trakt.lists.isEmpty, let error = trakt.listsError {
                EmptyStateView(systemImage: "exclamationmark.triangle",
                               title: "Couldn’t load lists", message: error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                listBody
            }
        }
        .task { await trakt.loadLists() }
    }

    @ViewBuilder
    private var listBody: some View {
        #if os(tvOS)
        LazyVStack(spacing: 8) {
            ForEach(trakt.lists) { list in
                NavigationLink(value: list) {
                    TraktListRow(list: list)
                }
                .buttonStyle(TVListRowButtonStyle())
            }
        }
        .focusSection()
        #else
        List {
            ForEach(trakt.lists) { list in
                NavigationLink(value: list) {
                    TraktListRow(list: list)
                }
                .listRowBackground(Theme.background)
            }
        }
        .listStyle(.plain)
        .hideScrollBackground()
        .refreshable { await trakt.loadLists(force: true) }
        #endif
    }
}

private struct TraktListRow: View {
    let list: TraktListSummary
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.subheadline.weight(.semibold))
                if let count = list.itemCount {
                    Text(count == 1 ? "1 title" : "\(count) titles")
                        .font(.caption)
                        .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .foregroundStyle(isFocused ? Color.black : Color.white)
    }

    private var icon: String {
        switch list.kind {
        case .watchlist: "bookmark"
        case .favorites: "heart"
        case .personal: "list.bullet"
        }
    }
}

struct TraktListItemsView: View {
    let list: TraktListSummary

    @State private var trakt = TraktStore.shared
    @State private var items: [MediaResult]?
    @State private var importedCount: Int?
    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        Group {
            if let items, !items.isEmpty {
                itemsBody(items)
            } else if trakt.loadingListID != nil || items == nil && trakt.itemsError == nil {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = trakt.itemsError {
                EmptyStateView(systemImage: "exclamationmark.triangle",
                               title: "Couldn’t load", message: error)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(systemImage: "tray",
                               title: "Empty list",
                               message: "No movies or shows in “\(list.name)” yet.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.background)
        .navigationTitle(list.name)
        .inlineNavigationBar()
        .task { items = await trakt.items(for: list) }
        .toolbar {
            if let items, !items.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        importedCount = trakt.importToWatchlist(items, watchlist: watchlist)
                    } label: {
                        Label("Add all to Watchlist", systemImage: "text.badge.plus")
                    }
                }
            }
        }
        .alert("Added to Watchlist", isPresented: Binding(
            get: { importedCount != nil },
            set: { if !$0 { importedCount = nil } })) {
            Button("OK") { importedCount = nil }
        } message: {
            let count = importedCount ?? 0
            Text(count == 0 ? "Everything here is already in your Watchlist."
                            : count == 1 ? "1 new title added." : "\(count) new titles added.")
        }
    }

    @ViewBuilder
    private func itemsBody(_ items: [MediaResult]) -> some View {
        #if os(tvOS)
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        TraktItemRow(item: item, inWatchlist: watchlist.contains(item.id))
                    }
                    .buttonStyle(TVListRowButtonStyle())
                    .contextMenu { watchlistButton(item) }
                }
            }
            .focusSection()
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
        #else
        List {
            ForEach(items) { item in
                NavigationLink(value: item) {
                    TraktItemRow(item: item, inWatchlist: watchlist.contains(item.id))
                }
                .listRowBackground(Theme.background)
                .swipeActions { watchlistButton(item) }
                .contextMenu { watchlistButton(item) }
            }
        }
        .listStyle(.plain)
        .hideScrollBackground()
        .refreshable {
            if let refreshed = await trakt.items(for: list, force: true) {
                self.items = refreshed
            }
        }
        #endif
    }

    @ViewBuilder
    private func watchlistButton(_ item: MediaResult) -> some View {
        let saved = watchlist.contains(item.id)
        Button {
            watchlist.toggle(id: item.id, mediaType: item.type,
                             title: item.name, posterURL: item.posterURL)
        } label: {
            Label(saved ? "Remove from Watchlist" : "Add to Watchlist",
                  systemImage: saved ? "bookmark.slash" : "bookmark")
        }
        .tint(Theme.accent)
    }
}

private struct TraktItemRow: View {
    let item: MediaResult
    let inWatchlist: Bool
    #if os(tvOS)
    @Environment(\.isFocused) private var isFocused
    #else
    private let isFocused = false
    #endif

    var body: some View {
        HStack(spacing: rowSpacing) {
            PosterImage(url: item.posterURL, cornerRadius: 6)
                .frame(width: posterWidth)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(titleFont)
                    .lineLimit(2)
                Text([typeLabel, item.year].compactMap { $0 }.joined(separator: " · "))
                    .font(subtitleFont)
                    .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.secondary)
            }

            Spacer(minLength: 0)

            if inWatchlist {
                Image(systemName: "bookmark.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, rowSpacing / 2)
        .foregroundStyle(isFocused ? Color.black : Color.white)
    }

    private var typeLabel: String {
        switch item.type {
        case .movie: "Movie"
        case .series: "TV Show"
        case .anime: "Anime"
        }
    }

    #if os(tvOS)
    private var posterWidth: CGFloat { 130 }
    private var rowSpacing: CGFloat { 28 }
    private var titleFont: Font { .title3.weight(.semibold) }
    private var subtitleFont: Font { .callout }
    #else
    private var posterWidth: CGFloat { 54 }
    private var rowSpacing: CGFloat { 12 }
    private var titleFont: Font { .subheadline.weight(.semibold) }
    private var subtitleFont: Font { .caption }
    #endif
}
