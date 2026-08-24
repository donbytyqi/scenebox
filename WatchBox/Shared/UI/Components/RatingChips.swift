//
//  RatingChips.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import SwiftUI

struct RatingChips: View {
    let ratings: MediaRatings?
    var fallbackIMDb: Double? = nil

    @ViewBuilder var body: some View {
        if let imdb = ratings?.imdb ?? fallbackIMDb {
            Chip(text: String(format: "IMDb %.1f", imdb), systemImage: "star.fill", tint: .yellow)
        }
        if let rt = ratings?.rottenTomatoes {
            Chip(text: "RT \(rt)%",
                 tint: rt >= 60 ? Color(red: 0.98, green: 0.31, blue: 0.15) : .green)
        }
        if let mc = ratings?.metacritic {
            Chip(text: "MC \(mc)")
        }
    }
}
