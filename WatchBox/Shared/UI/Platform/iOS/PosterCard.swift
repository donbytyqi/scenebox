//
//  PosterCard.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

#if os(iOS)
import SwiftUI

struct PosterCard: View {
    let item: MediaResult
    @Environment(WatchlistStore.self) private var watchlist: WatchlistStore?

    var body: some View {
        PosterImage(url: item.posterURL)
            .overlay(alignment: .topTrailing) {
                if watchlist?.contains(item.id) == true {
                    Image(systemName: "bookmark.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(6)
                }
            }
            .accessibilityLabel(item.name)
    }
}
#endif
