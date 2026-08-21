//
//  TVPosterCard.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

#if os(tvOS)
import SwiftUI

struct TVPosterCard: View {
    let item: MediaResult
    var width: CGFloat = 260
    @Environment(WatchlistStore.self) private var watchlist: WatchlistStore?

    var body: some View {
        PosterImage(url: item.posterURL)
            .frame(width: width)
            .overlay(alignment: .topTrailing) {
                if watchlist?.contains(item.id) == true {
                    Image(systemName: "bookmark.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(9)
                        .background(.black.opacity(0.55), in: Circle())
                        .padding(10)
                }
            }
            .accessibilityLabel(item.name)
    }
}
#endif
