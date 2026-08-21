//
//  MediaDetail.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import Foundation

nonisolated public struct MediaDetail: Identifiable, Sendable {
    public let id: String
    public let type: MediaType
    public let name: String
    public let year: String?
    public let posterURL: URL?
    public let backdropURL: URL?
    public let logoURL: URL?
    public let description: String?
    public let cast: [String]
    public let directors: [String]
    public let writers: [String]
    public let genres: [String]
    public let imdbRating: Double?
    public let runtime: String?
    public let released: Date?
    public let country: String?
    public let awards: String?
    public let episodes: [Episode]
    public var moviedbID: Int?
    public var trailerYouTubeIDs: [String] = []

    public var trailerURL: URL? {
        trailerYouTubeIDs.first.flatMap { URL(string: "https://www.youtube.com/watch?v=\($0)") }
    }

    public var seasons: [Int] {
        let numbered = Set(episodes.map(\.season))
        return numbered.filter { $0 > 0 }.sorted() + (numbered.contains(0) ? [0] : [])
    }

    public func episodes(inSeason season: Int) -> [Episode] {
        episodes.filter { $0.season == season }.sorted { $0.episode < $1.episode }
    }

    public var summaryLine: String {
        [year, runtime, genres.prefix(3).joined(separator: ", ")]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "  ·  ")
    }
}
