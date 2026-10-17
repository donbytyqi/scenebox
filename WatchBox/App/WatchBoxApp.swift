//
//  WatchBoxApp.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import SwiftVLC
import Kingfisher

@main
struct WatchBoxApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        // Configures Firebase from an imported plist if there is one, then a
        // bundled one, and otherwise leaves the app in guest/local mode instead
        // of trapping. `FirebaseApp.configure()` on its own calls `fatalError`
        // when no plist is present, which made the app unlaunchable before the
        // user had any way to supply one.
        _ = FirebaseConfigStore.shared

        Self.configureImageCache()

        _ = VLCInstance.prewarmShared()

        StreamCoordinator.pruneCacheAtLaunch()

    }

    private static func configureImageCache() {
        let storage = ImageCache.default.memoryStorage
        storage.config.totalCostLimit = 80 * 1024 * 1024
        storage.config.countLimit = 200
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .onOpenURL { DeepLinkRouter.shared.handle($0) }
        }
    }
}
