//
//  MacWindow.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import Foundation
import UIKit

enum MacWindow {
    nonisolated(unsafe) private static var cursorHidden = false

    @MainActor
    static func setCursorHidden(_ hidden: Bool) {
        guard Platform.isMac, hidden != cursorHidden,
              let cursor = NSClassFromString("NSCursor") as? NSObject.Type else { return }
        cursorHidden = hidden
        _ = cursor.perform(NSSelectorFromString(hidden ? "hide" : "unhide"))
    }

    @MainActor
    static func setTitle(_ title: String) {
        guard Platform.isMac else { return }
        for scene in UIApplication.shared.connectedScenes {
            (scene as? UIWindowScene)?.title = title
        }
    }

    @MainActor
    static func toggleFullScreen() {
        guard Platform.isMac,
              let appClass = NSClassFromString("NSApplication") as? NSObject.Type,
              let app = appClass.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? NSObject
        else { return }
        let window = (app.perform(NSSelectorFromString("keyWindow"))?.takeUnretainedValue() as? NSObject)
            ?? (app.perform(NSSelectorFromString("mainWindow"))?.takeUnretainedValue() as? NSObject)
            ?? ((app.perform(NSSelectorFromString("windows"))?.takeUnretainedValue() as? [NSObject])?.first)
        _ = window?.perform(NSSelectorFromString("toggleFullScreen:"), with: nil)
    }
}
#endif
