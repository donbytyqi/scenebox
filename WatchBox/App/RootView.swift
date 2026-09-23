//
//  RootView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI

struct RootView: View {
    @State private var auth = AuthStore()
    @State private var profiles = ProfileStore.shared
    @State private var externalStreamer: StreamCoordinator?
    @State private var links = DeepLinkRouter.shared

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                ZStack {
                    Theme.background.ignoresSafeArea()
                    ProgressView().tint(.white).controlSize(.large)
                }
                .preferredColorScheme(.dark)
            case .signedOut:
                if auth.isGuest, profiles.selected != nil {
                    RootTabView()
                } else {
                    LoginView()
                }
            case .signedIn:
                if profiles.selected != nil {
                    RootTabView()
                } else {
                    ProfilePickerView()
                }
            }
        }
        #if DEBUG
        .task { startAutoStreamIfRequested() }
        #endif
        .onChange(of: links.pendingMagnet) { _, magnet in
            guard let magnet else { return }
            links.pendingMagnet = nil
            play(magnet: magnet, fileIndex: nil, title: magnet.displayName ?? "Magnet link")
        }
        .fullScreenCover(isPresented: Binding(
            get: { externalStreamer?.isPresenting ?? false },
            set: { presented in if !presented { externalStreamer?.stop() } }
        )) {
            if let externalStreamer {
                StreamPlayerContainer(streamer: externalStreamer)
                    .environment(AppSettings.shared)
            }
        }
        .environment(auth)
        .environment(profiles)
        .onChange(of: auth.state, initial: true) { _, state in
            switch state {
            case .signedIn(let uid, _):
                profiles.activate(uid: uid)
                CloudSettingsSync.shared.activate(uid: uid)
            case .signedOut:
                if auth.isGuest { profiles.activateGuest() } else { profiles.deactivate() }
                CloudSettingsSync.shared.deactivate()
            case .loading:
                break
            }
        }
        .onChange(of: auth.isGuest) { _, guest in
            guard case .signedOut = auth.state else { return }
            if guest { profiles.activateGuest() } else { profiles.deactivate() }
        }
        .onChange(of: profiles.selected?.id, initial: true) { _, profileID in
            if case .signedIn(let uid, _) = auth.state, let profileID {
                if auth.pendingGuestMigration {
                    auth.pendingGuestMigration = false
                    Task {
                        await GuestMigration.migrate(uid: uid, profileID: profileID)
                        WatchProgressStore.shared.use(FirestoreWatchProgressBackend(uid: uid, profileID: profileID))
                        WatchlistStore.shared.use(FirestoreWatchlistBackend(uid: uid, profileID: profileID))
                    }
                    return
                }
                WatchProgressStore.shared.use(FirestoreWatchProgressBackend(uid: uid, profileID: profileID))
                WatchlistStore.shared.use(FirestoreWatchlistBackend(uid: uid, profileID: profileID))
            } else {
                WatchProgressStore.shared.use(LocalWatchProgressBackend())
                WatchlistStore.shared.use(LocalWatchlistBackend())
            }
        }
    }

    private func play(magnet: MagnetLink, fileIndex: Int?, title: String) {
        let stream = TorrentStream(
            id: magnet.infoHash.hexString,
            title: title,
            displayName: title,
            infoHash: magnet.infoHash,
            fileIndex: fileIndex,
            trackers: magnet.trackers,
            seeders: nil, sizeText: nil, resolution: nil, url: nil)
        let streamer = externalStreamer ?? StreamCoordinator()
        externalStreamer = streamer
        streamer.play(stream, title: stream.title, backdropURL: nil)
    }

    #if DEBUG
    private func startAutoStreamIfRequested() {
        guard externalStreamer == nil else { return }
        if let urlString = UserDefaults.standard.string(forKey: "WBAutoStreamURL"),
           let url = URL(string: urlString) {
            let streamer = StreamCoordinator()
            externalStreamer = streamer
            let progress = WatchProgressContext(
                mediaID: "tt0000001", mediaType: .movie, title: "Auto-stream URL test",
                posterURL: nil, season: nil, episode: nil, episodeID: nil,
                source: WatchSource(debridURLString: url.absoluteString))
            streamer.playDebrid(url: url, title: "Auto-stream URL test", backdropURL: nil, progress: progress)
            return
        }
        guard let magnetString = UserDefaults.standard.string(forKey: "WBAutoStreamMagnet"),
              let magnet = MagnetLink(string: magnetString) else { return }
        let fileIndex = UserDefaults.standard.object(forKey: "WBAutoStreamFileIndex") != nil
            ? UserDefaults.standard.integer(forKey: "WBAutoStreamFileIndex") : nil
        play(magnet: magnet, fileIndex: fileIndex, title: magnet.displayName ?? "Auto-stream test")
    }
    #endif
}
