//
//  TVCatalogView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 07.08.26.
//

#if os(tvOS)
import SwiftUI

struct TVCatalogView: View {
    @State private var model: CatalogModel
    @Environment(AppSettings.self) private var settings

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 300), spacing: 44)]

    init(type: MediaType, feed: CatalogFeed) {
        _model = State(initialValue: CatalogModel(type: type, feed: feed))
    }

    var body: some View {
        @Bindable var model = model

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 40) {
                header($model.feed, $model.genre)
                content
            }
            .padding(.horizontal, TVHomeView.edge)
            .padding(.top, 12)
            .padding(.bottom, 60)
        }
        .background(Theme.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: settings.streamSourceBases) { _, _ in model.applySettings(settings) }
        .task { model.loadIfNeeded() }
    }

    private func header(_ feed: Binding<CatalogFeed>, _ genre: Binding<String?>) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(model.type.browseTitle)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 16) {
                Menu {
                    Picker("Category", selection: feed) {
                        ForEach(CatalogFeed.allCases) { Text($0.title).tag($0) }
                    }
                } label: {
                    filterPill(icon: "line.3.horizontal.decrease", text: model.feed.title)
                }
                .buttonStyle(FilterPillStyle())

                Menu {
                    Picker("Genre", selection: genre) {
                        Text("All Genres").tag(String?.none)
                        ForEach(MediaGenre.shared, id: \.self) { Text($0).tag(String?.some($0)) }
                    }
                } label: {
                    filterPill(icon: "theatermasks", text: model.genre ?? "All Genres")
                }
                .buttonStyle(FilterPillStyle())
            }
        }
    }

    private func filterPill(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
            Text(text)
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.items.isEmpty {
            centered { ProgressView().tint(.white).controlSize(.large) }
        } else if model.items.isEmpty, let message = model.errorMessage {
            centered {
                EmptyStateView(systemImage: "exclamationmark.triangle",
                               title: "Couldn’t load", message: message)
            }
        } else {
            LazyVGrid(columns: columns, spacing: 56) {
                ForEach(model.items) { item in
                    NavigationLink(value: item) {
                        TVPosterCard(item: item)
                    }
                    .buttonStyle(TVPosterButtonStyle())
                    .onAppear { model.loadMoreIfNeeded(after: item) }
                }
            }
            .padding(.top, 16)

            if model.isPaging {
                ProgressView().tint(.white).padding(.top, 24)
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack { Spacer(); content(); Spacer() }
            .frame(maxWidth: .infinity, minHeight: 700)
    }
}

private struct FilterPillStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    struct Content: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.headline)
                .foregroundStyle(isFocused ? Color.black : .white)
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(isFocused ? Color.white : .white.opacity(0.12), in: Capsule())
                .scaleEffect(isFocused ? 1.05 : 1)
                .opacity(configuration.isPressed ? 0.7 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
#endif
