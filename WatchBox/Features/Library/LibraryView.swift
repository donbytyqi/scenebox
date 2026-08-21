//
//  LibraryView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

import SwiftUI

struct LibraryView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case downloads = "Downloads"
        case watchlist = "Watchlist"
        var id: String { rawValue }
    }

    @State private var section: Section = .downloads

    var body: some View {
        NavigationStack {
            Group {
                #if os(tvOS)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        PageTitleRow("Library")
                        sectionPicker
                        content
                    }
                    .padding(.horizontal, controlInset)
                    .padding(.top, 40)
                    .padding(.bottom, 60)
                }
                #else
                VStack(spacing: 0) {
                    sectionPicker
                        .padding(.horizontal, controlInset)
                        .padding(.top, 8)
                        .padding(.bottom, 4)
                    content
                }
                #endif
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .pageTitle("Library")
            .mediaNavigationDestinations()
        }
    }

    private var sectionPicker: some View {
        Picker("Section", selection: $section) {
            ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .downloads: DownloadsView()
        case .watchlist: WatchlistSection()
        }
    }

    #if os(tvOS)
    private var controlInset: CGFloat { TVHomeView.edge }
    #else
    private var controlInset: CGFloat { 16 }
    #endif
}

private struct WatchlistSection: View {
    @Environment(WatchlistStore.self) private var watchlist

    var body: some View {
        if watchlist.items.isEmpty {
            EmptyStateView(
                systemImage: "bookmark",
                title: "No saved titles",
                message: "Add movies and shows to your Watchlist from their detail pages.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if os(tvOS)
                .frame(minHeight: 500)   // hosted in a ScrollView: give it room
                #endif
        } else {
            #if os(tvOS)
            LazyVStack(spacing: 8) {
                ForEach(watchlist.items) { item in
                    NavigationLink(value: item.mediaResult) {
                        WatchlistRow(item: item)
                    }
                    .buttonStyle(TVListRowButtonStyle())
                    .contextMenu {
                        Button(role: .destructive) {
                            watchlist.remove(id: item.id)
                        } label: {
                            Label("Remove from Watchlist", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .focusSection()
            #else
            List {
                ForEach(watchlist.items) { item in
                    NavigationLink(value: item.mediaResult) {
                        WatchlistRow(item: item)
                    }
                    .listRowBackground(Theme.background)
                    .swipeActions {
                        Button(role: .destructive) {
                            watchlist.remove(id: item.id)
                        } label: {
                            Label("Remove", systemImage: "bookmark.slash")
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            watchlist.remove(id: item.id)
                        } label: {
                            Label("Remove from Watchlist", systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .hideScrollBackground()
            .refreshable { await watchlist.refresh() }
            #endif
        }
    }
}

private struct WatchlistRow: View {
    let item: WatchlistItem
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
                Text(item.title)
                    .font(titleFont)
                    .lineLimit(2)
                Text(typeLabel)
                    .font(subtitleFont)
                    .foregroundStyle(isFocused ? Color.black.opacity(0.6) : Color.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, rowSpacing / 2)
        .foregroundStyle(isFocused ? Color.black : Color.white)
    }

    private var typeLabel: String {
        switch item.mediaType {
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
