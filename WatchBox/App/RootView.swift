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
                LoginView()
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
                profiles.deactivate()
                CloudSettingsSync.shared.deactivate()
            case .loading:
                break
            }
        }
        .onChange(of: profiles.selected?.id, initial: true) { _, profileID in
            if case .signedIn(let uid, _) = auth.state, let profileID {
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
        guard externalStreamer == nil,
              let magnetString = UserDefaults.standard.string(forKey: "WBAutoStreamMagnet"),
              let magnet = MagnetLink(string: magnetString) else { return }
        let fileIndex = UserDefaults.standard.object(forKey: "WBAutoStreamFileIndex") != nil
            ? UserDefaults.standard.integer(forKey: "WBAutoStreamFileIndex") : nil
        play(magnet: magnet, fileIndex: fileIndex, title: magnet.displayName ?? "Auto-stream test")
    }
    #endif
}
