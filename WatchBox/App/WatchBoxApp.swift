//
//  WatchBoxApp.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import SwiftVLC
import Kingfisher
import FirebaseCore

@main
struct WatchBoxApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        FirebaseApp.configure()

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
