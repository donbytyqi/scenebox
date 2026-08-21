//
//  PersonCredit.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import Foundation

nonisolated public struct PersonCredit: Identifiable, Sendable, Hashable {
    public let id: Int          // TMDB title id
    public let type: MediaType  // .movie or .series
    public let title: String
    public let year: String?
    public let posterURL: URL?
}
