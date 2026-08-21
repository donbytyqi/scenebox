//
//  PosterImage.swift
//  SceneBox
//
//  Created by SpontaneousArray on 01.08.26.
//

import SwiftUI
import Kingfisher

struct PosterImage: View {
    let url: URL?
    var cornerRadius: CGFloat = Theme.posterCorner

    private static let decodeSize = CGSize(width: 500, height: 750)

    var body: some View {
        Rectangle()
            .fill(Theme.surface)
            .aspectRatio(Theme.posterAspect, contentMode: .fit)
            .overlay {
                KFImage(url)
                    .setProcessor(DownsamplingImageProcessor(size: Self.decodeSize))
                    .resizable()
                    .fade(duration: 0.2)
                    .cacheOriginalImage()
                    .placeholder {
                        Image(systemName: "film")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.2))
                    }
                    .scaledToFill()
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
