//
//  AppDelegate.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = ScreenOrientation.deviceDefault

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppDelegate.mask
    }
}

enum ScreenOrientation {
    static var deviceDefault: UIInterfaceOrientationMask {
        UIDevice.current.userInterfaceIdiom == .pad || Platform.isMac ? .all : .portrait
    }

    static func landscape() {
        guard !Platform.isMac else { return }
        AppDelegate.mask = .landscape
        request(.landscapeRight)
    }

    static func reset() {
        guard !Platform.isMac else { return }
        AppDelegate.mask = deviceDefault
        if UIDevice.current.userInterfaceIdiom != .pad { request(.portrait) }
    }

    private static func request(_ orientations: UIInterfaceOrientationMask) {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations))
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}
#endif
