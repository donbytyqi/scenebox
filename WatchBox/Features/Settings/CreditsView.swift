//
//  CreditsView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import SwiftUI

struct CreditsView: View {
    private struct Library: Identifiable {
        let name: String
        let detail: String
        let urlString: String
        var id: String { name }
        var url: URL? { URL(string: urlString) }
    }

    private let libraries: [Library] = [
        .init(name: "SwiftVLC",
              detail: "Swift wrapper around libVLC that powers video playback.",
              urlString: "https://github.com/harflabs/SwiftVLC"),
        .init(name: "VLC · libVLC",
              detail: "VideoLAN's media engine that SwiftVLC builds on.",
              urlString: "https://github.com/videolan/vlc"),
        .init(name: "Kingfisher",
              detail: "Asynchronous image downloading and caching.",
              urlString: "https://github.com/onevcat/Kingfisher"),
    ]

    var body: some View {
        List {
            PageTitleRow("Credits")
            Section {
                ForEach(libraries) { library in
                    row(for: library)
                }
            } header: {
                Text("Open source")
            } footer: {
                Text("Metadata comes from Stremio add-ons (Cinemeta, Torrentio, Kitsu) and OpenSubtitles. The app uses the TMDB API but is not endorsed or certified by TMDB.")
            }
        }
        .hideScrollBackground()
        .background(Theme.background)
        .pageTitle("Credits")
        .inlineNavigationBar()
    }

    @ViewBuilder
    private func row(for library: Library) -> some View {
        #if os(tvOS)
        VStack(alignment: .leading, spacing: 4) {
            Text(library.name).font(.headline).foregroundStyle(.white)
            Text(library.detail).font(.subheadline).foregroundStyle(.secondary)
            Text(library.urlString).font(.caption).foregroundStyle(.white.opacity(0.4))
        }
        .padding(.vertical, 4)
        #else
        if let url = library.url {
            Link(destination: url) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(library.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(library.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "arrow.up.right")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
        }
        #endif
    }
}
