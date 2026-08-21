//
//  PlaybackFormatting.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation
import SwiftVLC

func timecode(_ duration: Duration) -> String {
    let total = max(0, Int(duration.components.seconds))
    let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
        : String(format: "%d:%02d", minutes, seconds)
}

func trackLabel(for track: Track) -> String {
    guard let language = track.language, !language.isEmpty else { return track.name }
    return track.name.localizedCaseInsensitiveContains(language)
        ? track.name
        : "\(track.name) · \(language)"
}
