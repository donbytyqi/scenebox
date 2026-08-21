//
//  PlaybackSettingsPanel.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import SwiftUI
import SwiftVLC

struct PlaybackSettingsPanel: View {
    let player: Player
    let subs: SubtitlesController
    var onAudioSelected: () -> Void = {}
    let onClose: () -> Void

    private enum Page { case root, subtitles }
    @State private var page: Page = .root

    private let rates: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    switch page {
                    case .root:
                        header(title: "Playback")
                        if !player.audioTracks.isEmpty { audioSection }
                        subtitleNavSection
                        if hasActiveSubtitle { subtitleDelaySection }
                        speedSection
                        aspectSection
                    case .subtitles:
                        header(title: "Subtitles")
                        subtitleSection
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: panelWidth, maxHeight: .infinity)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .padding(panelInset)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.15), value: page == .root)
        #if os(tvOS)
        .onExitCommand {
            if page == .subtitles { page = .root } else { onClose() }
        }
        #endif
    }

    private func header(title: String) -> some View {
        HStack(spacing: 14) {
            if page != .root {
                #if os(tvOS)
                Button { page = .root } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(TVCircleButtonStyle(diameter: 46))
                #else
                Button { page = .root } label: {
                    Image(systemName: "chevron.left.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                #endif
            }
            Text(title)
                .font(.title3.weight(.bold))
            Spacer()
            if page == .root {
                #if os(tvOS)
                Button(action: onClose) { Image(systemName: "xmark") }
                    .buttonStyle(TVCircleButtonStyle(diameter: 46))
                #else
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.6))
                }
                .buttonStyle(.plain)
                #endif
            }
        }
    }

    private var audioSection: some View {
        SettingsSection(title: "Audio") {
            ForEach(uniqueTracks(player.audioTracks)) { track in
                OptionRow(title: trackLabel(for: track),
                          selected: player.selectedAudioTrack?.id == track.id) {
                    player.selectedAudioTrack = track
                    onAudioSelected()
                }
            }
        }
    }

    private var subtitleNavSection: some View {
        SettingsSection(title: "Subtitles") {
            NavRow(title: "Language", value: currentSubtitleLabel) { page = .subtitles }
        }
    }

    private var subtitleSection: some View {
        SettingsSection(title: "Language") {
            OptionRow(title: "Off", selected: !hasActiveSubtitle) {
                subs.apply(nil, on: player)
                page = .root
            }

            ForEach(subs.embeddedTracks(of: player)) { track in
                OptionRow(title: trackLabel(for: track),
                          selected: subs.embeddedID == track.id) {
                    subs.selectEmbedded(track, on: player)
                    page = .root
                }
            }

            if subs.isLoading {
                Label("Loading…", systemImage: "arrow.triangle.2.circlepath")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.6))
            }
            ForEach(subs.byLanguage, id: \.language) { group in
                if let track = group.tracks.first {
                    OptionRow(title: group.language,
                              selected: group.tracks.contains { $0.id == subs.selectedID }) {
                        subs.apply(track, on: player)
                        page = .root
                    }
                }
            }
        }
    }

    private var currentSubtitleLabel: String {
        if let id = subs.embeddedID,
           let track = subs.embeddedTracks(of: player).first(where: { $0.id == id }) {
            return trackLabel(for: track)
        }
        if let group = subs.byLanguage.first(where: { group in
            group.tracks.contains { $0.id == subs.selectedID }
        }) {
            return group.language
        }
        return "Off"
    }

    private var subtitleDelaySection: some View {
        SettingsSection(title: "Subtitle sync") {
            HStack(spacing: 16) {
                Button { adjustSubtitleDelay(by: -0.25) } label: {
                    Image(systemName: "minus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text(delayText).font(.headline.monospacedDigit())
                    Text(delayHint).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)

                Button { adjustSubtitleDelay(by: 0.25) } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var speedSection: some View {
        SettingsSection(title: "Speed") {
            ForEach(rates, id: \.self) { rate in
                OptionRow(title: String(format: "%.2g×", rate),
                          selected: abs(player.rate - rate) < 0.01) {
                    try? player.setPlaybackRate(PlaybackRate(rate))
                }
            }
        }
    }

    private var aspectSection: some View {
        SettingsSection(title: "Aspect ratio") {
            aspectRow("Fit", .default)
            aspectRow("Fill", .fill)
            aspectRow("16:9", .ratio(16, 9))
            aspectRow("4:3", .ratio(4, 3))
        }
    }

    private func aspectRow(_ title: String, _ ratio: AspectRatio) -> some View {
        OptionRow(title: title, selected: player.aspectRatio == ratio) {
            player.aspectRatio = ratio
        }
    }

    private func uniqueTracks(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.id).inserted }
    }

    private var hasActiveSubtitle: Bool {
        subs.embeddedID != nil || subs.selectedID != nil
    }

    private var delaySeconds: Double {
        let c = player.subtitleDelay.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    private var delayText: String { String(format: "%+.2f s", delaySeconds) }

    private var delayHint: String {
        if abs(delaySeconds) < 0.01 { return "in sync" }
        return delaySeconds > 0 ? "later" : "earlier"
    }

    private func adjustSubtitleDelay(by seconds: Double) {
        let millis = Int((delaySeconds + seconds) * 1000)
        try? player.setSubtitleDelay(.milliseconds(millis))
    }

    #if os(tvOS)
    private var panelWidth: CGFloat { 560 }
    private var panelInset: CGFloat { 48 }
    #else
    private var panelWidth: CGFloat { 360 }
    private var panelInset: CGFloat { 12 }
    #endif
}

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
                #if os(tvOS)
                .padding(.leading, 16)   // line the header up with the row text inset
                #endif
            content
        }
    }
}

struct OptionRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        Button(action: action) { Text(title).lineLimit(1) }
            .buttonStyle(OptionRowStyle(selected: selected))
        #else
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        #endif
    }
}

struct NavRow: View {
    let title: String
    let value: String
    let action: () -> Void

    var body: some View {
        #if os(tvOS)
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title).lineLimit(1)
                Spacer(minLength: 8)
                Text(value).lineLimit(1).opacity(0.6)
                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .opacity(0.6)
            }
        }
        .buttonStyle(NavRowStyle())
        #else
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.body)
                Spacer(minLength: 8)
                Text(value)
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(.white.opacity(0.55))
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .contentShape(Rectangle())
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        #endif
    }
}

#if os(tvOS)
private struct NavRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration)
    }

    struct Row: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .font(.title3)
                .foregroundStyle(isFocused ? .black : .white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(isFocused ? Color.white : .clear,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .scaleEffect(isFocused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}

private struct OptionRowStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Row(configuration: configuration, selected: selected)
    }

    struct Row: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            HStack(spacing: 12) {
                configuration.label
                    .font(.title3)
                Spacer(minLength: 8)
                if selected {
                    Image(systemName: "checkmark").font(.title3.weight(.semibold))
                }
            }
            .foregroundStyle(isFocused ? .black : .white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .scaleEffect(isFocused ? 1.02 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
        }

        private var rowBackground: Color {
            if isFocused { return .white }
            return selected ? .white.opacity(0.1) : .clear
        }
    }
}
#endif
