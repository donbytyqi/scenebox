//
//  ActorView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import SwiftUI
import Kingfisher

struct ActorView: View {
    let member: CastMember

    @Environment(AppSettings.self) private var settings
    @State private var credits: [PersonCredit] = []
    @State private var isLoading = true

    #if os(tvOS)
    private let columns = [GridItem(.adaptive(minimum: 200, maximum: 240), spacing: 40)]
    private let edge: CGFloat = 80
    #else
    private let columns = [GridItem(.adaptive(minimum: 108, maximum: 160), spacing: 12)]
    private let edge: CGFloat = 16
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if isLoading && credits.isEmpty {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity).padding(.top, 60)
                } else if credits.isEmpty {
                    EmptyStateView(systemImage: "film", title: "No titles",
                                   message: "Couldn’t load this person’s filmography.")
                        .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(columns: columns, spacing: 24) {
                        ForEach(credits) { credit in
                            NavigationLink(value: credit) {
                                CreditCard(credit: credit)
                            }
                            #if os(tvOS)
                            .buttonStyle(.card)
                            #else
                            .buttonStyle(.plain)
                            #endif
                        }
                    }
                    .padding(.horizontal, edge)
                    .padding(.bottom, 40)
                }
            }
        }
        .background(Theme.background)
        #if os(iOS)
        .navigationTitle(member.name)
        .navigationBarTitleDisplayMode(.inline)
        #else
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .task {
            guard credits.isEmpty else { return }
            defer { isLoading = false }
            guard let tmdb = TMDBClient(key: settings.tmdbAPIKey) else { return }
            credits = await tmdb.filmography(personID: member.id)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: headerSpacing) {
            KFImage(member.photoURL)
                .resizable()
                .placeholder {
                    Image(systemName: "person.fill")
                        .font(.system(size: headerPhoto * 0.4))
                        .foregroundStyle(.white.opacity(0.3))
                }
                .scaledToFill()
                .frame(width: headerPhoto, height: headerPhoto)
                .background(Theme.surface)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(member.name).font(headerFont).foregroundStyle(.white)
                if let role = member.role, !role.isEmpty {
                    Text("as \(role)").font(headerSub).foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, edge)
        .padding(.top, headerTop)
    }

    #if os(tvOS)
    private var headerPhoto: CGFloat { 200 }
    private var headerSpacing: CGFloat { 40 }
    private var headerTop: CGFloat { 60 }
    private var headerFont: Font { .system(size: 56, weight: .bold) }
    private var headerSub: Font { .title3 }
    #else
    private var headerPhoto: CGFloat { 96 }
    private var headerSpacing: CGFloat { 16 }
    private var headerTop: CGFloat { 8 }
    private var headerFont: Font { .title.weight(.bold) }
    private var headerSub: Font { .subheadline }
    #endif
}

private struct CreditCard: View {
    let credit: PersonCredit

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            PosterImage(url: credit.posterURL)
            Text(credit.title)
                .font(titleFont)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(credit.year ?? " ")
                .font(yearFont)
                .foregroundStyle(.white.opacity(0.55))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }

    #if os(tvOS)
    private var titleFont: Font { .callout.weight(.medium) }
    private var yearFont: Font { .caption }
    private var spacing: CGFloat { 8 }
    #else
    private var titleFont: Font { .caption.weight(.medium) }
    private var yearFont: Font { .caption2 }
    private var spacing: CGFloat { 3 }
    #endif
}
