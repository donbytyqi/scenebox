//
//  TVPosterShelf.swift
//  SceneBox
//
//  Created by SpontaneousArray on 16.08.26.
//

#if os(tvOS)
import SwiftUI

struct TVPosterShelf: View {
    let title: String
    let items: [MediaResult]
    var destination: CatalogDestination? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, TVHomeView.edge)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 40) {
                    ForEach(items) { item in
                        NavigationLink(value: item) {
                            TVPosterCard(item: item)
                        }
                        .buttonStyle(TVPosterButtonStyle())
                    }
                    if let destination {
                        NavigationLink(value: destination) {
                            TVSeeAllCard()
                        }
                        .buttonStyle(TVPosterButtonStyle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, TVHomeView.edge)
                .padding(.vertical, 24)
            }
            .scrollClipDisabled()
        }
        .focusSection()
    }
}

private struct TVSeeAllCard: View {
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "chevron.forward.circle.fill").font(.system(size: 64))
            Text("See All").font(.title3.weight(.semibold))
        }
        .foregroundStyle(.white.opacity(0.9))
        .frame(width: 260, height: 390)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
#endif
