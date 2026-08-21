//
//  MediaType.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation

nonisolated public enum MediaType: String, Sendable, Codable {
    case movie, series, anime

    public var browseTitle: String {
        switch self {
        case .movie: "Movies"
        case .series: "TV Shows"
        case .anime: "Anime"
        }
    }
}
