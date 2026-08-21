//
//  PlaybackScreen.swift
//  SceneBox
//
//  Created by SpontaneousArray on 19.08.26.
//

import SwiftUI
import SwiftVLC
import UIKit
#if DEBUG
import OSLog

private let playbackLog = Logger(subsystem: "WatchBox", category: "playback")
#endif

struct PlaybackScreen: View {
    let url: URL
    let title: String
    let stats: SwarmStats?
    var subtitleContext: SubtitleContext? = nil
    var episodes: EpisodePlaylist? = nil
    var startAt: Duration = .zero
    var progress: WatchProgressContext? = nil
    var artworkURL: URL? = nil
    var originalAudioLanguage: String? = nil
    let onClose: () -> Void

    @Environment(AppSettings.self) private var settings

    @State private var player = Player()
    #if os(iOS)
    @State private var nowPlaying: NowPlayingController?
    #endif
    @State private var chrome = ChromeVisibility()
    @State private var subs = SubtitlesController()
    @State private var failure: String?
    @State private var isStalled = false
    @State private var didSeekToStart = false
    @State private var openRetries = 0
    @State private var knownDuration: Duration = .zero
    @State private var upNextSecondsLeft: Int?
    @State private var upNextCancelled = false
    @State private var didAutoAdvance = false
    @State private var originalAudioSatisfied = false
    #if os(iOS)
    @State private var isLandscape = false
    @FocusState private var hasKeyboardFocus: Bool
    @State private var lastHoverReveal = Date.distantPast
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VideoView(player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                #if os(tvOS)
                .allowsHitTesting(false)
                .focusable(false)
                #endif

            #if os(iOS)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard Platform.isMac else { return }
                    MacWindow.toggleFullScreen()
                }
                .onTapGesture {
                    guard failure == nil else { return }
                    chrome.screenTapped(shouldAutoHide: player.isPlaying && !isBuffering)
                }
                .ignoresSafeArea()
            #endif

            if let failure {
                FailureOverlay(message: failure, onClose: onClose)
            } else if chrome.isVisible {
                #if os(tvOS)
                TVPlaybackChrome(
                    player: player,
                    title: title,
                    stats: stats,
                    isBuffering: isBuffering,
                    subs: subs,
                    onSettingsOpenChanged: { open in
                        open ? chrome.holdVisible()
                             : chrome.releaseHold(autoHide: player.isPlaying && !isBuffering)
                    },
                    onInteraction: { chrome.interacted(autoHide: player.isPlaying && !isBuffering) },
                    onAudioSelected: { originalAudioSatisfied = true },
                    episodes: episodes,
                    onClose: onClose
                )
                .transition(.opacity)
                #else
                PlaybackControls(
                    player: player,
                    title: title,
                    stats: stats,
                    isBuffering: isBuffering,
                    subs: subs,
                    onSettingsOpenChanged: { open in
                        open ? chrome.holdVisible()
                             : chrome.releaseHold(autoHide: player.isPlaying && !isBuffering)
                    },
                    isLandscape: isLandscape,
                    onToggleOrientation: toggleOrientation,
                    onAudioSelected: { originalAudioSatisfied = true },
                    episodes: episodes,
                    onClose: onClose
                )
                .transition(.opacity)
                #endif
            }

            #if os(tvOS)
            if failure == nil, !chrome.isVisible {
                Button {
                    chrome.screenTapped(shouldAutoHide: player.isPlaying && !isBuffering)
                } label: {
                    Color.clear
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(InvisibleButtonStyle())
                .ignoresSafeArea()
            }
            #endif

            if let seconds = upNextSecondsLeft, let episodes, let next = episodes.next {
                UpNextCard(episode: next,
                           isNewSeason: episodes.nextIsNewSeason,
                           seconds: seconds) {
                    upNextCancelled = true
                    upNextSecondsLeft = nil
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(.trailing, upNextTrailingInset)
                .padding(.bottom, chrome.isVisible ? upNextRaisedInset : upNextBottomInset)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: upNextSecondsLeft != nil)
        .contentShape(Rectangle())
        #if os(iOS)
        .focusable()
        .focusEffectDisabled()
        .focused($hasKeyboardFocus)
        .onAppear { hasKeyboardFocus = true }
        .onKeyPress(.space) { keyboardTogglePlayback(); return .handled }
        .onKeyPress(.leftArrow) { keyboardSeek(by: -10); return .handled }
        .onKeyPress(.rightArrow) { keyboardSeek(by: 10); return .handled }
        .onKeyPress(.upArrow) { keyboardVolume(by: 0.05); return .handled }
        .onKeyPress(.downArrow) { keyboardVolume(by: -0.05); return .handled }
        .onKeyPress(.escape) { keyboardEscape(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "kK")) { _ in keyboardTogglePlayback(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "fF")) { _ in MacWindow.toggleFullScreen(); return .handled }
        .onChange(of: chrome.isVisible, initial: true) { _, visible in
            MacWindow.setCursorHidden(!visible && failure == nil)
        }
        .onDisappear { MacWindow.setCursorHidden(false) }
        .onContinuousHover { phase in
            guard case .active = phase, failure == nil else { return }
            let now = Date()
            guard now.timeIntervalSince(lastHoverReveal) > 0.5 else { return }
            lastHoverReveal = now
            chrome.reveal(autoHide: player.isPlaying && !isBuffering)
        }
        #endif
        #if os(tvOS)
        .onPlayPauseCommand { player.togglePlaybackReasserting() }
        .onMoveCommand { _ in
            guard failure == nil, !chrome.isVisible else { return }
            chrome.reveal(autoHide: player.isPlaying && !isBuffering)
        }
        .onExitCommand {
            if upNextSecondsLeft != nil {
                upNextCancelled = true
                upNextSecondsLeft = nil
            } else if chrome.isVisible {
                chrome.hide()
            } else {
                onClose()
            }
        }
        #endif
        .hideStatusBarCompat()
        .hideSystemOverlaysCompat()
        .preferredColorScheme(.dark)
        .task(id: chrome.autoHideID) { await chrome.autoHide() }
        .task { await watchForStalls() }
        .task { await watchForUpNext() }
        .task { await recordProgressPeriodically() }
        .task { await keepNowPlayingFresh() }
        .task(id: openRetries) {
            guard openRetries > 0 else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            beginPlayback()
        }
        #if DEBUG
        .task { await reportPlayerTime() }
        .task { await monitorPlayback() }
        .task { await runAutoSeekScript() }
        #endif
        .onChange(of: player.isSeekable) { _, seekable in
            guard seekable, !didSeekToStart, startAt > .zero else { return }
            didSeekToStart = true
            try? player.seek(to: startAt)
        }
        .onAppear(perform: start)
        .onChange(of: player.isPlaying) { _, playing in
            ScreenIdle.keepAwake(playing)
            #if os(iOS)
            nowPlaying?.refresh()
            #endif
            guard failure == nil, !isBuffering else { return }
            if playing {
                if chrome.isVisible { chrome.playbackStarted() }
            } else {
                chrome.reveal(autoHide: false)
            }
        }
        .onChange(of: player.subtitleTracks.count) { _, _ in
            subs.syncEmbedded(on: player)
        }
        .onChange(of: player.selectedSubtitleTrack?.id) { _, _ in
            subs.syncEmbedded(on: player)
        }
        .onChange(of: player.audioTracks.count) { _, _ in
            syncOriginalAudio()
        }
        .onChange(of: player.duration) { _, new in
            if let new, new > .zero { knownDuration = new }
        }
        .onChange(of: player.didReachEnd) { _, ended in
            if ended { playbackEnded() }
        }
        .onChange(of: isBuffering) { wasBuffering, buffering in
            if wasBuffering, !buffering { chrome.playbackStarted() }
        }
        .onChange(of: player.state) { _, state in
            guard state == .error, failure == nil else { return }
            if url.host == "127.0.0.1", player.currentTime == .zero, openRetries < 5 {
                player.stop()
                openRetries += 1
            } else {
                failure = "Playback failed. The release may be corrupt or use an unsupported container."
            }
        }
        .onDisappear(perform: teardown)
    }

    private var isBuffering: Bool {
        guard failure == nil else { return false }
        switch player.state {
        case .opening, .buffering: return true
        case .playing: return player.currentTime == .zero || isStalled
        default: return false
        }
    }

    private func watchForStalls() async {
        var lastSeen = player.currentTime
        var frozenTicks = 0

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            guard player.isPlaying else {
                frozenTicks = 0
                isStalled = false
                lastSeen = player.currentTime
                continue
            }

            if player.currentTime == lastSeen {
                frozenTicks += 1
            } else {
                frozenTicks = 0
                lastSeen = player.currentTime
            }
            isStalled = frozenTicks >= 3
        }
    }

    // MARK: - Auto-play next episode

    #if os(tvOS)
    private var upNextTrailingInset: CGFloat { 80 }
    private var upNextBottomInset: CGFloat { 60 }
    private var upNextRaisedInset: CGFloat { 210 }
    #else
    private var upNextTrailingInset: CGFloat { 20 }
    private var upNextBottomInset: CGFloat { 24 }
    private var upNextRaisedInset: CGFloat { 120 }
    #endif

    private func watchForUpNext() async {
        guard episodes?.next != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            guard !upNextCancelled, !didAutoAdvance, failure == nil,
                  knownDuration > .zero, player.currentTime > .zero else {
                upNextSecondsLeft = nil
                continue
            }
            let remaining = knownDuration - player.currentTime
            guard remaining > .zero, remaining <= .seconds(10) else {
                upNextSecondsLeft = nil
                continue
            }
            upNextSecondsLeft = max(1, Int(remaining.asSeconds.rounded(.up)))
        }
    }

    private func playbackEnded() {
        if let progress, knownDuration > .zero {
            WatchProgressStore.shared.record(
                id: progress.mediaID, mediaType: progress.mediaType, title: progress.title,
                posterURL: progress.posterURL, season: progress.season,
                episode: progress.episode, episodeID: progress.episodeID,
                position: knownDuration, duration: knownDuration)
        }
        guard !upNextCancelled, !didAutoAdvance,
              let episodes, let next = episodes.next else { return }
        didAutoAdvance = true
        upNextSecondsLeft = nil
        episodes.onPlay(next)
    }

    // MARK: - Original-language audio

    private var targetAudioLanguage: String? {
        let preferred = settings.preferredAudioLanguage.lowercased()
        let original = originalAudioLanguage?.lowercased()
        if preferred.isEmpty { return original?.isEmpty == false ? original : nil }
        guard let original, !original.isEmpty, original != preferred else { return preferred }
        return original
    }

    private func syncOriginalAudio() {
        guard !originalAudioSatisfied, let code = targetAudioLanguage else { return }
        var seen = Set<String>()
        let tracks = player.audioTracks.filter { seen.insert($0.id).inserted }
        guard tracks.count > 1 else { return }   // more may still be discovered

        if let selected = player.selectedAudioTrack,
           OriginalAudio.matches(selected, language: code) {
            originalAudioSatisfied = true
            return
        }
        guard let match = tracks.first(where: { OriginalAudio.matches($0, language: code) }) else { return }
        player.selectedAudioTrack = match
        originalAudioSatisfied = true
    }

    #if DEBUG
    private func reportPlayerTime() async {
        guard !url.isFileURL else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            PlayheadTelemetry.shared.notePlayerTime(seconds: player.currentTime.asSeconds)
        }
    }

    private func runAutoSeekScript() async {
        guard url.host == "127.0.0.1",
              let script = UserDefaults.standard.string(forKey: "WBAutoSeekScript") else { return }
        var steps: [(at: Double, delta: Double)] = []
        for part in script.split(separator: ",") {
            let bits = part.split(separator: ":")
            guard bits.count == 2, let at = Double(bits[0]), let delta = Double(bits[1]) else { continue }
            steps.append((at: at, delta: delta))
        }
        steps.sort { $0.at < $1.at }
        guard !steps.isEmpty else { return }
        while player.currentTime == .zero, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
        }
        let playbackStarted = Date()
        for step in steps {
            while Date().timeIntervalSince(playbackStarted) < step.at, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
            }
            guard !Task.isCancelled, failure == nil else { return }
            let target = player.currentTime + .seconds(step.delta)
            playbackLog.notice("autoseek: \(step.delta >= 0 ? "+" : "", privacy: .public)\(Int(step.delta), privacy: .public)s → t=\(Int(target.asSeconds), privacy: .public)s")
            try? player.seek(to: target)
        }
    }

    private func monitorPlayback() async {
        guard !url.isFileURL else { return }
        var last = player.currentTime
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            let now = player.currentTime
            let delta = (now - last).asSeconds
            last = now
            let stalled = player.isPlaying && delta < 0.25

            playbackLog.notice("""
            \(stalled ? "STALL" : "ok", privacy: .public) · playing=\(player.isPlaying, privacy: .public) \
            playhead=\(timecode(now), privacy: .public) Δ=\(String(format: "%.2f", delta), privacy: .public)s \
            state=\(String(describing: player.state), privacy: .public) buffering=\(isBuffering, privacy: .public)
            """)
        }
    }
    #endif

    private func start() {
        player.aspectRatio = settings.fillScreen ? .fill : .default
        player.setSubtitleScale(SubtitleScale(Float(settings.subtitleScale)))
        Task {
            await PlaybackAudioSession.activate()
            beginPlayback()
            #if os(iOS)
            let controller = NowPlayingController(player: player, title: title)
            controller.begin(artworkURL: artworkURL)
            nowPlaying = controller
            #endif
        }
    }

    private func keepNowPlayingFresh() async {
        #if os(iOS)
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            nowPlaying?.refresh()
        }
        #endif
    }

    private func beginPlayback() {
        do {
            let media = try Media(url: url)
            if !url.isFileURL {
                let isTorrent = url.host == "127.0.0.1"
                let cacheMs = isTorrent
                    ? max(settings.networkCacheMilliseconds, 8000)
                    : settings.networkCacheMilliseconds
                media.addOption(":network-caching=\(cacheMs)")

                if isTorrent {
                } else {
                    media.addOption(":http-reconnect")
                }
            }
            try player.play(media)
        } catch {
            failure = error.localizedDescription
        }

        if let subtitleContext {
            subs.load(context: subtitleContext, preferred: settings.preferredSubtitleLanguage, player: player)
        }
    }

    #if os(iOS)
    private func keyboardTogglePlayback() {
        guard failure == nil else { return }
        player.togglePlaybackReasserting()
        chrome.reveal(autoHide: !player.isPlaying && !isBuffering)
    }

    private func keyboardSeek(by seconds: Double) {
        guard failure == nil, player.isSeekable else { return }
        try? player.seek(by: .seconds(seconds), fast: true)
        chrome.reveal(autoHide: player.isPlaying && !isBuffering)
    }

    private func keyboardVolume(by delta: Float) {
        try? player.setAudioVolume(Volume(min(1, max(0, player.volume + delta))))
        chrome.reveal(autoHide: player.isPlaying && !isBuffering)
    }

    private func keyboardEscape() {
        if upNextSecondsLeft != nil {
            upNextCancelled = true
            upNextSecondsLeft = nil
        } else if chrome.isVisible, player.isPlaying {
            chrome.hide()
        } else {
            onClose()
        }
    }

    private func toggleOrientation() {
        isLandscape.toggle()
        isLandscape ? ScreenOrientation.landscape() : ScreenOrientation.reset()
    }
    #endif

    private func recordProgressPeriodically() async {
        guard progress != nil else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            if player.isPlaying { recordProgress() }
        }
    }

    private func recordProgress() {
        guard let progress, failure == nil else { return }
        guard player.currentTime > .zero else { return }
        WatchProgressStore.shared.record(
            id: progress.mediaID, mediaType: progress.mediaType, title: progress.title,
            posterURL: progress.posterURL, season: progress.season,
            episode: progress.episode, episodeID: progress.episodeID,
            position: player.currentTime, duration: player.duration)
    }

    private func teardown() {
        #if os(iOS)
        nowPlaying?.end()
        nowPlaying = nil
        #endif
        recordProgress()
        chrome.viewDisappeared()
        ScreenIdle.keepAwake(false)
        #if os(iOS)
        ScreenOrientation.reset()
        #endif

        let player = player
        Task {
            await player.stopAndWait()
            PlaybackAudioSession.deactivate()
        }
    }
}

#if os(tvOS)
private struct InvisibleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
#endif

private struct FailureOverlay: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(message)
                .multilineTextAlignment(.center)
                .font(.callout)
            Button("Close", action: onClose)
                .buttonStyle(.borderedProminent)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }
}
