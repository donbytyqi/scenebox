//
//  UpNextCard.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import SwiftUI

struct UpNextCard: View {
    let episode: Episode
    let isNewSeason: Bool
    let seconds: Int
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(isNewSeason ? "New Season" : "Up Next")
                    .font(eyebrowFont)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.accent)

                Text("Season \(episode.season) Episode \(episode.episode)")
                    .font(titleFont)
                    .lineLimit(1)

                Text("Playing in \(seconds)s")
                    .font(countdownFont.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.65))
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.default, value: seconds)

                #if os(tvOS)
                Text("Press Back to cancel")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.top, 2)
                #endif
            }

            #if os(iOS)
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            #endif
        }
        .foregroundStyle(.white)
        .padding(cardPadding)
        .frame(maxWidth: cardWidth, alignment: .leading)
        .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        )
        .shadow(color: .black.opacity(0.4), radius: 14, y: 4)
    }

    #if os(tvOS)
    private var eyebrowFont: Font { .caption.weight(.bold) }
    private var titleFont: Font { .title3.weight(.semibold) }
    private var countdownFont: Font { .body }
    private var cardPadding: CGFloat { 24 }
    private var cardWidth: CGFloat { 560 }
    #else
    private var eyebrowFont: Font { .caption2.weight(.bold) }
    private var titleFont: Font { .subheadline.weight(.semibold) }
    private var countdownFont: Font { .footnote }
    private var cardPadding: CGFloat { 16 }
    private var cardWidth: CGFloat { 320 }
    #endif
}
