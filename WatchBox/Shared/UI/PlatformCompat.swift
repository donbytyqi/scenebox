//
//  PlatformCompat.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI

extension View {
    func inlineNavigationBar() -> some View {
        #if os(iOS)
        return navigationBarTitleDisplayMode(.inline)
        #else
        return self
        #endif
    }

    func hideStatusBarCompat() -> some View {
        #if os(iOS)
        return statusBarHidden(true)
        #else
        return self
        #endif
    }

    func hideSystemOverlaysCompat() -> some View {
        #if os(iOS)
        return persistentSystemOverlays(.hidden)
        #else
        return self
        #endif
    }

    func hideScrollBackground() -> some View {
        #if os(tvOS)
        return self
        #else
        return scrollContentBackground(.hidden)
        #endif
    }
}

enum Platform {
    nonisolated static let isMac: Bool = ProcessInfo.processInfo.isMacCatalystApp
}

enum ScreenIdle {
    #if os(iOS)
    nonisolated(unsafe) private static var macActivity: NSObjectProtocol?
    #endif

    static func keepAwake(_ awake: Bool) {
        #if os(iOS)
        if Platform.isMac {
            if awake, macActivity == nil {
                macActivity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleDisplaySleepDisabled, .userInitiated], reason: "Video playback")
            } else if !awake, let activity = macActivity {
                ProcessInfo.processInfo.endActivity(activity)
                macActivity = nil
            }
            return
        }
        #endif
        #if os(iOS) || os(tvOS)
        UIApplication.shared.isIdleTimerDisabled = awake
        #endif
    }
}
