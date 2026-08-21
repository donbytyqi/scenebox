//
//  TVPlaybackChrome.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

#if os(tvOS)
import SwiftUI
import SwiftVLC

struct TVPlaybackChrome: View {
    let player: Player
    let title: String
    let stats: SwarmStats?
    var isBuffering: Bool = false
    let subs: SubtitlesController
    var onSettingsOpenChanged: (Bool) -> Void = { _ in }
    var onInteraction: () -> Void = {}
    var onAudioSelected: () -> Void = {}
    var episodes: EpisodePlaylist? = nil
    let onClose: () -> Void

    @State private var showSettings = false
    @State private var showEpisodes = false
    @State private var knownDuration: Duration = .zero
    @State private var seekFlash: SeekFlash?
    @State private var lastRewindAt: Date?
    @FocusState private var focus: Field?

    private let doubleSwipeWindow: TimeInterval = 0.65

    private enum Field: Hashable { case scrubber, playPause, cc, episodes, nextEpisode }
    private struct SeekFlash: Equatable { let forward: Bool; let token: Int }

    var body: some View {
        ZStack {
            scrim

            if isPaused {
                Color.black.opacity(0.35).ignoresSafeArea()
            }

            VStack(alignment: .leading, spacing: 0) {
                topBar
                Spacer(minLength: 0)
                bottom
            }
            .padding(.horizontal, 80)
            .padding(.top, 56)
            .padding(.bottom, 52)

            if let flash = seekFlash { seekIndicator(flash) }

            if showSettings {
                PlaybackSettingsPanel(player: player, subs: subs,
                                      onAudioSelected: onAudioSelected) { showSettings = false }
                    .transition(.opacity)
            }

            if showEpisodes, let episodes {
                TVEpisodePanel(episodes: episodes,
                               onPlay: { episode in showEpisodes = false; episodes.onPlay(episode) },
                               onClose: { showEpisodes = false })
                    .transition(.opacity)
            }
        }
        .foregroundStyle(.white)
        .defaultFocus($focus, .scrubber)
        .animation(.easeInOut(duration: 0.15), value: showSettings)
        .animation(.easeInOut(duration: 0.15), value: showEpisodes)
        .animation(.easeInOut(duration: 0.2), value: isPaused)
        .onChange(of: showSettings) { _, open in onSettingsOpenChanged(open) }
        .onChange(of: showEpisodes) { _, open in onSettingsOpenChanged(open) }
        .onChange(of: focus) { _, _ in
            lastRewindAt = nil
            onInteraction()
        }
        .onChange(of: player.duration) { _, new in if let new, new > .zero { knownDuration = new } }
        .onAppear { if let d = player.duration, d > .zero { knownDuration = d } }
        .task(id: seekFlash?.token) {
            guard seekFlash != nil else { return }
            try? await Task.sleep(for: .seconds(0.9))
            if !Task.isCancelled { seekFlash = nil }
        }
    }

    // MARK: - Top

    private var topBar: some View {
        HStack(alignment: .top, spacing: 24) {
            metadata
            Spacer(minLength: 0)
            optionControls
        }
    }

    private var optionControls: some View {
        HStack(spacing: 18) {
            if episodes != nil {
                Button { showEpisodes = true } label: {
                    TVChromeIcon(systemName: "list.bullet", isFocused: focus == .episodes)
                }
                .buttonStyle(BareButtonStyle())
                .focused($focus, equals: .episodes)

                if episodes?.next != nil {
                    Button {
                        if let next = episodes?.next { episodes?.onPlay(next) }
                    } label: {
                        TVChromeIcon(systemName: "forward.end.fill", isFocused: focus == .nextEpisode)
                    }
                    .buttonStyle(BareButtonStyle())
                    .focused($focus, equals: .nextEpisode)
                }
            }
            chromeButton("captions.bubble", field: .cc)
        }
        .focusSection()
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let episode = titleParts.episode {
                Text(episode)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Text(titleParts.main)
                .font(.system(size: 46, weight: .bold))
                .lineLimit(2)
            if let ends = endsAtText {
                Text(ends)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(maxWidth: 1000, alignment: .leading)
        .shadow(radius: 12)
    }

    // MARK: - Bottom

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isBuffering { bufferingLine }

            HStack(alignment: .center, spacing: 24) {
                Button {
                    player.togglePlaybackReasserting()
                    onInteraction()
                } label: {
                    TVChromeIcon(systemName: player.isPlaying ? "pause.fill" : "play.fill",
                                 isFocused: focus == .playPause)
                }
                .buttonStyle(BareButtonStyle())
                .focused($focus, equals: .playPause)
                .onMoveCommand { direction in
                    switch direction {
                    case .up: focus = episodes != nil ? .episodes : .cc
                    case .right: focus = .scrubber
                    default: break
                    }
                }

                ScrubberBar(player: player, knownDuration: knownDuration,
                            focused: focus == .scrubber, buffering: isBuffering)
                    .focusable()
                    .focused($focus, equals: .scrubber)
                    .onMoveCommand { direction in
                        switch direction {
                        case .left:
                            if let last = lastRewindAt,
                               Date().timeIntervalSince(last) < doubleSwipeWindow {
                                lastRewindAt = nil
                                focus = .playPause
                            } else {
                                lastRewindAt = Date()
                                seek(-10)
                            }
                        case .right:
                            lastRewindAt = nil
                            seek(10)
                        case .down: focus = .playPause
                        default: break
                        }
                    }
            }
        }
    }

    private func chromeButton(_ name: String, field: Field) -> some View {
        Button { showSettings = true } label: {
            TVChromeIcon(systemName: name, isFocused: focus == field)
        }
        .buttonStyle(BareButtonStyle())
        .focused($focus, equals: field)
    }

    private var bufferingLine: some View {
        HStack(spacing: 14) {
            ProgressView().tint(.white)
            Text(stats?.connectedPeers == 0 ? "Connecting…" : "Buffering…")
            if let stats {
                Text("· \(stats.connectedPeers) peers · \(ByteFormat.rate(stats.downloadRate))")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .font(.callout.monospacedDigit())
    }

    // MARK: - ±10s indicator

    private func seekIndicator(_ flash: SeekFlash) -> some View {
        VStack(spacing: 10) {
            Image(systemName: flash.forward ? "goforward.10" : "gobackward.10")
                .font(.system(size: 72, weight: .regular))
            Text(timecode(player.currentTime))
                .font(.title2.monospacedDigit())
        }
        .foregroundStyle(.white)
        .padding(40)
        .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(radius: 20)
        .transition(.opacity)
    }

    private func seek(_ seconds: Double) {
        try? player.seek(by: .seconds(seconds), fast: true)
        seekFlash = SeekFlash(forward: seconds > 0, token: (seekFlash?.token ?? 0) + 1)
        onInteraction()
    }

    // MARK: - Scrim

    private var scrim: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Derived

    private var isPaused: Bool { !player.isPlaying && !isBuffering }

    private var titleParts: (main: String, episode: String?) {
        let parts = title.components(separatedBy: " · ")
        guard parts.count >= 2, let code = parts.last,
              let eIndex = code.firstIndex(of: "E"),
              code.hasPrefix("S")
        else { return (title, nil) }
        let main = parts.dropLast().joined(separator: " · ")
        let episode = "\(code[..<eIndex]) · \(code[eIndex...])"   // S4E11 -> "S4 · E11"
        return (main, episode)
    }

    private var endsAtText: String? {
        let remaining = knownDuration - player.currentTime
        guard knownDuration > .zero, remaining > .zero else { return nil }
        let end = Date().addingTimeInterval(Double(remaining.components.seconds))
        return "Ends at \(end.formatted(date: .omitted, time: .shortened))"
    }
}

private struct ScrubberBar: View {
    let player: Player
    let knownDuration: Duration
    let focused: Bool
    let buffering: Bool

    var body: some View {
        VStack(spacing: 12) {
            GeometryReader { geo in
                let fraction = max(0, min(1, player.position))
                let height: CGFloat = focused ? 10 : 5
                let knob: CGFloat = focused ? 32 : 0
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.25)).frame(height: height)
                    Capsule().fill(.white).frame(width: geo.size.width * fraction, height: height)
                    Circle()
                        .fill(.white)
                        .frame(width: knob, height: knob)
                        .offset(x: geo.size.width * fraction - knob / 2)
                        .shadow(radius: 6)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 34)

            HStack {
                Text(timecode(player.currentTime))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(timecode(remaining))")
                    .foregroundStyle(.white.opacity(0.6))
            }
            .font(.callout.monospacedDigit())
        }
        .opacity(buffering ? 0.5 : 1)
        .animation(.easeOut(duration: 0.15), value: focused)
    }

    private var remaining: Duration {
        let r = knownDuration - player.currentTime
        return r > .zero ? r : .zero
    }
}

private struct TVChromeIcon: View {
    let systemName: String
    let isFocused: Bool

    static let diameter: CGFloat = 52

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 24, weight: .medium))
            .foregroundStyle(isFocused ? Color.black : .white)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(isFocused ? Color.white : Color.white.opacity(0.12), in: Circle())
            .scaleEffect(isFocused ? 1.06 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

private struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

// MARK: - Preview

private struct TVPlaybackChromePreview: View {
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
            TVPlaybackChrome(
                player: player,
                title: "House of the Dragon · S1E1",
                stats: sampleStats,
                isBuffering: buffering,
                subs: SubtitlesController(),
                onClose: {}
            )
        }
    }
}

#Preview("tvOS Player") {
    TVPlaybackChromePreview(buffering: false)
}

#Preview("tvOS Player · Buffering") {
    TVPlaybackChromePreview(buffering: true)
}
#endif
