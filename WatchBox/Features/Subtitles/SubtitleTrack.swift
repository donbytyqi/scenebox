//
//  SubtitleTrack.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import Foundation

nonisolated struct SubtitleTrack: Identifiable, Sendable, Hashable {
    let id: String
    let languageCode: String   // ISO 639-2, e.g. "eng"
    let url: URL

    var languageName: String { SubtitleLanguage.displayName(for: languageCode) }
}
