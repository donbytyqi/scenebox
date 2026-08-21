//
//  RootTabView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI

struct RootTabView: View {
    @State private var settings = AppSettings.shared
    @State private var downloads = DownloadStore.shared
    @State private var watchProgress = WatchProgressStore.shared
    @State private var watchlist = WatchlistStore.shared
    @Environment(ProfileStore.self) private var profiles
    @State private var profileIcon: UIImage?
    #if os(iOS)
    @State private var detailItem: MediaResult?
    @State private var links = DeepLinkRouter.shared
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    var body: some View {
        TabView {
            #if os(tvOS)
            Tab("Home", systemImage: "house.fill") {
                TVHomeView()
            }
            Tab("Search", systemImage: "magnifyingglass") {
                TVSearchView()
            }
            #else
            Tab("Home", systemImage: "house.fill") {
                HomeView()
            }
            Tab("Search", systemImage: "magnifyingglass") {
                SearchView()
            }
            #endif

            Tab("Library", systemImage: "books.vertical") {
                LibraryView()
            }
            #if !os(tvOS)
            .badge(downloads.activeCount)
            #endif

            #if os(tvOS)
            Tab("Profile", systemImage: "person.crop.circle") {
                ProfileView()
            }
            #else
            Tab {
                ProfileView()
            } label: {
                Label {
                    Text("Profile")
                } icon: {
                    if let profileIcon {
                        Image(uiImage: profileIcon).renderingMode(.original)
                    } else {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            #endif
        }
        .task(id: profiles.selected) {
            guard let profile = profiles.selected else { profileIcon = nil; return }
            profileIcon = await ProfileTabIcon.make(for: profile)
        }
        .tint(settings.accentColor)
        .environment(settings)
        .environment(downloads)
        .environment(watchProgress)
        .environment(watchlist)
        .preferredColorScheme(.dark)
        #if os(iOS)
        .environment(\.openMediaDetail, sizeClass == .regular && !Platform.isMac ? { detailItem = $0 } : nil)
        .onChange(of: links.pendingDetail) { _, item in
            guard let item else { return }
            links.pendingDetail = nil
            detailItem = item
        }
        .sheet(item: $detailItem) { item in
            NavigationStack {
                MediaDetailView(mediaID: item.id, type: item.type, fallbackTitle: item.name)
                    .mediaNavigationDestinations()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") { detailItem = nil }
                        }
                    }
            }
            .environment(settings)
            .environment(downloads)
            .environment(watchProgress)
            .environment(watchlist)
            .environment(\.openMediaDetail, nil)
            .preferredColorScheme(.dark)
        }
        #endif
    }
}
