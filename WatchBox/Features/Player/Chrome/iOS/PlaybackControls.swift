//
//  PlaybackControls.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

#if os(iOS)
import SwiftUI
import SwiftVLC

struct PlaybackControls: View {
    let player: Player
    let title: String
    let stats: SwarmStats?
    var isBuffering: Bool = false
    let subs: SubtitlesController
    var onSettingsOpenChanged: (Bool) -> Void = { _ in }
    var isLandscape = false
    var onToggleOrientation: () -> Void = {}
    var onAudioSelected: () -> Void = {}
    var episodes: EpisodePlaylist? = nil
    let onClose: () -> Void

    @State private var showSettings = false
    @State private var showEpisodes = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBar(title: title, isLandscape: isLandscape,
                       onToggleOrientation: onToggleOrientation,
                       onSettings: { showSettings = true },
                       episodes: episodes,
                       onShowEpisodes: { showEpisodes = true },
                       onClose: onClose)
                Spacer(minLength: 0)
                TransportRow(player: player, isBuffering: isBuffering)
                Spacer(minLength: 0)
                BottomBar(player: player, stats: stats, isBuffering: isBuffering)
            }
            .foregroundStyle(.white)

            if showSettings {
                PlaybackSettingsPanel(player: player, subs: subs,
                                      onAudioSelected: onAudioSelected) { showSettings = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showSettings)
        .onChange(of: showSettings) { _, open in onSettingsOpenChanged(open) }
        .sheet(isPresented: $showEpisodes) {
            if let episodes {
                EpisodePickerSheet(episodes: episodes) { episode in
                    showEpisodes = false
                    episodes.onPlay(episode)
                }
            }
        }
        .onChange(of: showEpisodes) { _, open in onSettingsOpenChanged(open) }
    }
}

private struct TopBar: View {
    let title: String
    var isLandscape = false
    var onToggleOrientation: () -> Void = {}
    let onSettings: () -> Void
    var episodes: EpisodePlaylist? = nil
    var onShowEpisodes: () -> Void = {}
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Button(action: onClose) { icon("xmark") }

            Text(title)
                .font(Platform.isMac ? .headline.weight(.semibold) : .subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 4)

            Spacer(minLength: 0)

            if let episodes {
                Button(action: onShowEpisodes) { icon("list.bullet") }
                if let next = episodes.next {
                    Button { episodes.onPlay(next) } label: { icon("forward.end.fill") }
                }
            }

            if UIDevice.current.userInterfaceIdiom != .pad, !Platform.isMac {
                Button(action: onToggleOrientation) {
                    icon(isLandscape ? "arrow.down.right.and.arrow.up.left"
                                     : "arrow.up.left.and.arrow.down.right")
                }
            }
            Button(action: onSettings) { icon("slider.horizontal.3") }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(colors: [.black.opacity(0.75), .clear],
                           startPoint: .top, endPoint: .bottom)
        )
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .font(Platform.isMac ? .headline.weight(.bold) : .subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: Platform.isMac ? 44 : 40, height: Platform.isMac ? 44 : 40)
            .background(.ultraThinMaterial, in: Circle())
    }
}

private struct TransportRow: View {
    let player: Player
    let isBuffering: Bool

    var body: some View {
        let glyph: CGFloat = Platform.isMac ? 36 : 30
        let playSize: CGFloat = Platform.isMac ? 88 : 74
        HStack(spacing: Platform.isMac ? 64 : 48) {
            Button {
                try? player.seek(by: .seconds(-10), fast: true)
            } label: {
                Image(systemName: "gobackward.10").font(.system(size: glyph))
            }
            .disabled(!player.isSeekable)

            ZStack {
                if isBuffering, player.currentTime == .zero {
                    ProgressView().controlSize(.large).tint(.white)
                } else {
                    Button {
                        player.togglePlaybackReasserting()
                    } label: {
                        if #available(iOS 26.0, *) {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: glyph, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: playSize, height: playSize)
                                .glassEffect(.regular.interactive(), in: Circle())
                                .contentShape(Rectangle())
                        } else {
                        }
                    }
                }
            }
            .frame(width: playSize, height: playSize)

            Button {
                try? player.seek(by: .seconds(10), fast: true)
            } label: {
                Image(systemName: "goforward.10").font(.system(size: glyph))
            }
            .disabled(!player.isSeekable)
        }
        .buttonStyle(.plain)
        .shadow(radius: 8)
    }
}

private struct BottomBar: View {
    let player: Player
    let stats: SwarmStats?
    let isBuffering: Bool

    var body: some View {
        VStack(spacing: Platform.isMac ? 16 : 12) {
            SeekRow(player: player)
            if let stats { StatsRow(stats: stats, isBuffering: isBuffering) }
        }
        .padding(.horizontal, Platform.isMac ? 32 : 20)
        .padding(.top, Platform.isMac ? 28 : 16)
        .padding(.bottom, Platform.isMac ? 24 : 12)
        .background(
            LinearGradient(colors: [.clear, .black.opacity(0.75)],
                           startPoint: .top, endPoint: .bottom)
        )
    }
}

private struct SeekRow: View {
    let player: Player

    @State private var scrub: Double?
    @State private var pendingTarget: Double?
    @State private var knownDuration: Duration = .zero

    private var sliderValue: Double { scrub ?? pendingTarget ?? player.position }

    var body: some View {
        HStack(spacing: Platform.isMac ? 18 : 12) {
            Text(timecode(elapsed))
                .font(Platform.isMac ? .subheadline.monospacedDigit() : .caption.monospacedDigit())

            Slider(
                value: Binding(get: { sliderValue }, set: { scrub = $0 }),
                in: 0...1,
                onEditingChanged: { editing in
                    guard !editing, let target = scrub else { return }
                    seek(to: target)
                    pendingTarget = target
                    scrub = nil
                }
            )
            .tint(.white)
            .controlSize(Platform.isMac ? .large : .regular)
            .disabled(!player.isSeekable)

            Text(timecode(knownDuration))
                .font(Platform.isMac ? .subheadline.monospacedDigit() : .caption.monospacedDigit())
        }
        .onChange(of: player.duration) { _, new in
            if let new, new > .zero { knownDuration = new }
        }
        .onChange(of: player.position) { _, position in
            if let target = pendingTarget, abs(position - target) < 0.01 {
                pendingTarget = nil
            }
        }
    }

    private var elapsed: Duration {
        guard knownDuration > .zero else { return player.currentTime }
        if let fraction = scrub ?? pendingTarget {
            return .seconds(Double(knownDuration.components.seconds) * fraction)
        }
        return player.currentTime
    }

    private func seek(to position: Double) {
        if !player.seek(toPosition: PlaybackPosition(position), fast: true) {
            try? player.seek(to: PlaybackPosition(position))
        }
    }
}

private struct StatsRow: View {
    let stats: SwarmStats
    let isBuffering: Bool

    var body: some View {
        HStack(spacing: 16) {
            if isBuffering {
                Label(stats.connectedPeers == 0 ? "Connecting…" : "Buffering…",
                      systemImage: "arrow.triangle.2.circlepath")
            }
            Label("\(stats.connectedPeers)", systemImage: "person.2.fill")
            Label(ByteFormat.rate(stats.downloadRate), systemImage: "arrow.down.circle.fill")
            Spacer(minLength: 0)
        }
        .font(Platform.isMac ? .caption.monospacedDigit() : .caption2.monospacedDigit())
        .foregroundStyle(.white.opacity(0.75))
        .labelStyle(.titleAndIcon)
    }
}

// MARK: - Preview

private struct PlaybackControlsPreview: View {
    @State private var player = Player()
    let buffering: Bool

    private var sampleStats: SwarmStats {
        var stats = SwarmStats()
        stats.connectedPeers = 48
        stats.downloadRate = 3_400_000
        stats.progress = 0.02
        return stats
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.12, green: 0.10, blue: 0.20), .black],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            PlaybackControls(
                player: player,
                title: "Masters of the Universe",
                stats: sampleStats,
                isBuffering: buffering,
                subs: SubtitlesController(),
                isLandscape: true,
                onToggleOrientation: {},
                onClose: {}
            )
        }
    }
}

#Preview("iOS Player") {
    PlaybackControlsPreview(buffering: false)
}

#Preview("iOS Player · Buffering") {
    PlaybackControlsPreview(buffering: true)
}
#endif
