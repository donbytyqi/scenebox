//
//  TVBackdrop.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

#if os(tvOS)
import SwiftUI
import Kingfisher

struct TVBackdropImage: View {
    let url: URL?

    var body: some View {
        GeometryReader { geo in
            KFImage(url)
                .resizable()
                .fade(duration: 0.3)
                .placeholder { Theme.surface }
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
    }
}

struct TVTitleArt: View {
    let logoURL: URL?
    let title: String
    var maxLogoWidth: CGFloat = 560
    var maxLogoHeight: CGFloat = 190
    var titleSize: CGFloat = 64

    var body: some View {
        if let logoURL {
            KFImage(logoURL)
                .resizable()
                .placeholder { text }
                .scaledToFit()
                .frame(maxWidth: maxLogoWidth, maxHeight: maxLogoHeight, alignment: .leading)
        } else {
            text
        }
    }

    private var text: some View {
        Text(title)
            .font(.system(size: titleSize, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(2)
            .minimumScaleFactor(0.6)
    }
}
#endif
