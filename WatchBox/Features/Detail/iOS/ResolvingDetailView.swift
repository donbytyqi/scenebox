//
//  ResolvingDetailView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import SwiftUI

struct ResolvingDetailView: View {
    let credit: PersonCredit

    @Environment(AppSettings.self) private var settings
    @State private var imdbID: String?
    @State private var failed = false

    var body: some View {
        Group {
            if let imdbID {
                MediaDetailView(mediaID: imdbID, type: credit.type, fallbackTitle: credit.title)
            } else if failed {
                EmptyStateView(systemImage: "film", title: credit.title,
                               message: "Couldn’t find a matching entry to open.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            } else {
                ProgressView().tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
            }
        }
        .task {
            guard imdbID == nil, !failed else { return }
            guard let tmdb = TMDBClient(key: settings.tmdbAPIKey) else { failed = true; return }
            if let id = await tmdb.imdbID(tmdbID: credit.id, type: credit.type) {
                imdbID = id
            } else {
                failed = true
            }
        }
    }
}
