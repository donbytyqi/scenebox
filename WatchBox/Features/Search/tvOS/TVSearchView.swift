//
//  TVSearchView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 01.08.26.
//

#if os(tvOS)
import SwiftUI

struct TVSearchView: View {
    @State private var model = SearchModel()
    @Environment(AppSettings.self) private var settings
    @FocusState private var fieldFocused: Bool

    private let columns = [GridItem(.adaptive(minimum: 260, maximum: 300), spacing: 44)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 36) {
                    PageTitleRow("Search")
                    searchField
                    content
                }
                .padding(.horizontal, TVHomeView.edge)
                .padding(.top, 40)
                .padding(.bottom, 60)
            }
            .background(Theme.background.ignoresSafeArea())
            .pageTitle("Search")
            .mediaNavigationDestinations()
            .defaultFocus($fieldFocused, true)
        }
        .onChange(of: model.query) { _, query in
            if query.trimmingCharacters(in: .whitespaces).isEmpty { return }
            model.run()
        }
        .onChange(of: settings.streamSourceBases) { _, _ in
            model.applySettings(settings)
            if model.isSearching { model.run() }
        }
    }

    private var searchField: some View {
        HStack(spacing: 18) {
            Image(systemName: "magnifyingglass")
                .font(.title2.weight(.semibold))
                .foregroundStyle(fieldFocused ? Color.black.opacity(0.7) : .white.opacity(0.6))
            TextField("Search movies, shows & anime", text: $model.query)
                .textFieldStyle(.plain)
                .font(.title3)
                .foregroundStyle(fieldFocused ? Color.black : .white)
                .tint(fieldFocused ? Color.black : .white)
                .focused($fieldFocused)
                .onSubmit { model.run(immediate: true) }
            if model.isSearching, model.isLoading {
                ProgressView()
                    .tint(fieldFocused ? Color.black : .white)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(fieldFocused ? Color.white : Color.white.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .scaleEffect(fieldFocused ? 1.01 : 1)
        .animation(.easeOut(duration: 0.15), value: fieldFocused)
        .focusSection()
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoading && model.results.isEmpty {
            centered { ProgressView().tint(.white).controlSize(.large) }
        } else if !model.isSearching {
            centered {
                EmptyStateView(systemImage: "magnifyingglass",
                               title: "Search",
                               message: "Find any movie, show, or anime by name.")
            }
        } else if model.results.isEmpty {
            centered {
                EmptyStateView(systemImage: "magnifyingglass",
                               title: "No results",
                               message: model.errorMessage ?? "Nothing matched your search.")
            }
        } else {
            LazyVGrid(columns: columns, spacing: 56) {
                ForEach(model.results) { item in
                    NavigationLink(value: item) {
                        TVPosterCard(item: item)
                    }
                    .buttonStyle(TVPosterButtonStyle())
                    .onAppear { model.loadMoreIfNeeded(after: item) }
                }
            }
            .padding(.vertical, 24)
            .focusSection()

            if model.isLoadingMore {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
            }
        }
    }

    private func centered<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 500)
    }
}
#endif
