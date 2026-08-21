//
//  EpisodePlaylist.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation

@MainActor
struct EpisodePlaylist {
    let current: Episode
    let all: [Episode]
    let onPlay: (Episode) -> Void

    var next: Episode? {
        let ordered = all
            .filter { $0.season > 0 }
            .sorted { ($0.season, $0.episode) < ($1.season, $1.episode) }
        guard let index = ordered.firstIndex(of: current), index + 1 < ordered.count else { return nil }
        return ordered[index + 1]
    }

    var nextIsNewSeason: Bool {
        guard let next else { return false }
        return next.season != current.season
    }

    var seasons: [Int] { Array(Set(all.map(\.season))).sorted() }

    func episodes(inSeason season: Int) -> [Episode] {
        all.filter { $0.season == season }.sorted { $0.episode < $1.episode }
    }
}
