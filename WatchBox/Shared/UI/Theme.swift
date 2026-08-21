//
//  Theme.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import SwiftUI

enum Theme {
    static let background = Color(red: 0.05, green: 0.05, blue: 0.07)
    static let surface = Color(red: 0.10, green: 0.10, blue: 0.13)

    static var accent: Color { AppSettings.shared.accentColor }

    static let defaultAccentHex = "EEE600"

    static let accentPresets: [String] = [
        "EEE600",
        "FFD60A",
        "FF9F0A",
        "FF7A00",
        "FF453A",
        "FF375F",
        "BF5AF2",
        "5E5CE6",
        "0A84FF",
        "64D2FF",
        "30D158",
        "66D4CF",
    ]

    static var onAccent: Color { accent.contrastingForeground }

    static let posterCorner: CGFloat = 10
    static let posterAspect: CGFloat = 2.0 / 3.0
}
