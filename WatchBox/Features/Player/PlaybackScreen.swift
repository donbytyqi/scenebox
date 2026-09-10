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
    @State private var pip: PiPController?
    #endif
    @State private var chrome = ChromeVisibility()
    @State private var subs = SubtitlesController()
    @State private var failure: String?
    @State private var isStalled = false
    @State private var isRecoveringVideo = false
    @State private var videoRecoveries = 0
    @State private var recovery = PlaybackRecovery()
    @State private var pendingResume: Duration?
    @State private var retryID = 0
    @State private var isReconnecting = false
    @State private var isActive = false
    @State private var didFinishPlayback = false
    @State private var resumeAudio: Track?
    @State private var resumeSubtitle: Track?
    @State private var resumeExternalSubtitle: SubtitleTrack?
    @State private var restoreSelections = false
    @State private var resumeSubtitlesRestored = false
    @State private var knownDuration: Duration = .zero
    @State private var upNextSecondsLeft: Int?
    @State private var upNextCancelled = false
    @State private var didAutoAdvance = false
    @State private var originalAudioSatisfied = false
    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    @State private var isLandscape = false
    @FocusState private var hasKeyboardFocus: Bool
    @State private var lastHoverReveal = Date.distantPast
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            #if os(iOS)
            PiPVideoView(player, controller: $pip, managesAudioSession: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
            #else
            VideoView(player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
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
                FailureOverlay(message: failure, onRetry: retryPlayback, onClose: onClose)
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
                    pip: pip,
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
        .task { await watchForFrozenVideo() }
        .task { await watchForUpNext() }
        .task { await recordProgressPeriodically() }
        .task { await keepNowPlayingFresh() }
        .task(id: retryID) { await reconnectPlayback() }
        #if DEBUG
        .task { await reportPlayerTime() }
        .task { await monitorPlayback() }
        .task { await runAutoSeekScript() }
        #endif
        .onChange(of: player.isSeekable) { _, _ in restoreResumePosition() }
        .onChange(of: player.currentTime) { _, time in
            guard isActive, !isReconnecting, !isRecoveringVideo, pendingResume == nil,
                  player.state == .playing || player.state == .paused else { return }
            recovery.position = time
        }
        .onAppear(perform: start)
        #if os(iOS)
        .onChange(of: pip, initial: true) { _, controller in
            controller?.onRestoreUserInterface = { restore in restore(true) }
        }
        #endif
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
            if restoreSelections { restorePlaybackSelections() }
            else { subs.syncEmbedded(on: player) }
        }
        .onChange(of: player.selectedSubtitleTrack?.id) { _, _ in
            if !restoreSelections { subs.syncEmbedded(on: player) }
        }
        .onChange(of: player.audioTracks.count) { _, _ in
            if restoreSelections { restorePlaybackSelections() }
            else { syncOriginalAudio() }
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
            guard isActive, failure == nil, !isReconnecting, !isRecoveringVideo else { return }
            if state == .error {
                requestReconnect()
            } else if state == .playing {
                restoreResumePosition()
                if restoreSelections { restorePlaybackSelections() }
            }
        }
        .onDisappear(perform: teardown)
    }

    private var isBuffering: Bool {
        guard failure == nil else { return false }
        if isReconnecting { return true }
        switch player.state {
        case .opening, .buffering: return true
        case .playing: return player.currentTime == .zero || isStalled
        default: return false
        }
    }

    private func watchForStalls() async {
        var lastSeen = player.currentTime
        var frozenTicks = 0
        let clock = ContinuousClock()
        var lastCheck = clock.now

        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            let now = clock.now
            let elapsed = lastCheck.duration(to: now)
            lastCheck = now
            let expectedToAdvance = isActive && failure == nil && !didFinishPlayback
                && !isReconnecting && !isRecoveringVideo
                && (player.state == .playing || player.state == .opening || player.state == .error
                    || player.state == .buffering
                    || (player.state == .stopped && recovery.endedPrematurely(duration: knownDuration)))
            if isNetworkStream, recovery.observe(time: pendingResume ?? player.currentTime, elapsed: elapsed,
                                                expectedToAdvance: expectedToAdvance,
                                                timeout: .seconds(url.host == "127.0.0.1" ? 45 : 20)) {
                requestReconnect()
            }
            restoreResumePosition()
            if restoreSelections { restorePlaybackSelections() }

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

    // MARK: - Interrupted stream recovery

    private var isNetworkStream: Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    private func requestReconnect() {
        guard isActive, !isReconnecting, !isRecoveringVideo, !didFinishPlayback else { return }
        guard isNetworkStream,
              recovery.reserveRetry(limit: url.host == "127.0.0.1" ? 5 : 3) else {
            failure = "Playback was interrupted. Retry to resume, or choose another source."
            player.stop()
            chrome.reveal(autoHide: false)
            return
        }
        // Keep the previous selection if another attempt fails before tracks arrive.
        if !restoreSelections {
            resumeAudio = player.selectedAudioTrack
            resumeSubtitle = player.selectedSubtitleTrack
            resumeExternalSubtitle = subs.available.first { $0.id == subs.selectedID }
            restoreSelections = true
            resumeSubtitlesRestored = false
        }
        isReconnecting = true
        pendingResume = recovery.position > .zero ? recovery.position : nil
        upNextSecondsLeft = nil
        retryID += 1
        chrome.reveal(autoHide: false)
    }

    private func reconnectPlayback() async {
        guard retryID > 0, isActive, isReconnecting else { return }
        #if DEBUG
        playbackLog.notice("stream interrupted: reconnecting (attempt \(recovery.attempts, privacy: .public))")
        #endif
        await player.stopAndWait()
        try? await Task.sleep(for: .seconds(min(recovery.attempts, 3)))
        guard !Task.isCancelled, isActive else { return }
        isReconnecting = false
        beginPlayback()
    }

    private func retryPlayback() {
        failure = nil
        recovery.resetAttempts()
        if isNetworkStream {
            requestReconnect()
        } else {
            pendingResume = recovery.position > .zero ? recovery.position : nil
            beginPlayback()
        }
    }

    private func restoreResumePosition() {
        guard isActive, !isReconnecting, !isRecoveringVideo, failure == nil,
              player.isSeekable, player.state == .playing || player.state == .paused,
              let target = pendingResume else { return }
        do {
            try player.seek(to: target)
            pendingResume = nil
        } catch {
            // Seekability can precede demuxer readiness. Retry on the next tick.
        }
    }

    private func restorePlaybackSelections() {
        guard !isReconnecting, !isRecoveringVideo, player.isPlaying else { return }
        if let audio = resumeAudio,
           let match = matchingTrack(audio, in: player.audioTracks) {
            player.selectedAudioTrack = match
            resumeAudio = nil
        }
        if resumeSubtitlesRestored {
            // Audio tracks can arrive after the subtitle selection was restored.
        } else if let external = resumeExternalSubtitle {
            subs.apply(external, on: player)
            resumeExternalSubtitle = nil
            resumeSubtitle = nil
            resumeSubtitlesRestored = true
        } else if let subtitle = resumeSubtitle,
                  let match = matchingTrack(subtitle, in: player.subtitleTracks) {
            subs.selectEmbedded(match, on: player)
            resumeSubtitle = nil
            resumeSubtitlesRestored = true
        } else if resumeSubtitle == nil, resumeExternalSubtitle == nil {
            player.selectedSubtitleTrack = nil
            resumeSubtitlesRestored = true
        }
        restoreSelections = resumeAudio != nil || !resumeSubtitlesRestored
    }

    private func matchingTrack(_ track: Track, in tracks: [Track]) -> Track? {
        tracks.first { $0.id == track.id }
            ?? tracks.first { $0.name == track.name && $0.language == track.language }
            ?? tracks.first { track.language != nil && $0.language == track.language }
    }

    // MARK: - Frozen video recovery

    private var videoOutputExpected: Bool {
        guard player.videoTracks.contains(where: \.isSelected) else { return false }
        #if os(iOS)
        if scenePhase != .active { return false }
        #endif
        return true
    }

    // Audio drives VLC's clock. If time keeps moving but the frame counter
    // doesn't, the video output died on us and needs a rebuild.
    private func watchForFrozenVideo() async {
        var lastDisplayed: UInt64 = 0
        var lastTime = player.currentTime
        var frozenTicks = 0

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }

            guard failure == nil, !isReconnecting, !isRecoveringVideo, player.isPlaying, !isBuffering,
                  videoOutputExpected, let stats = player.statistics else {
                frozenTicks = 0
                lastDisplayed = player.statistics?.displayedPictures ?? 0
                lastTime = player.currentTime
                continue
            }

            let advanced = (player.currentTime - lastTime).asSeconds
            if stats.displayedPictures == lastDisplayed, advanced >= 0.7 {
                frozenTicks += 1
            } else {
                frozenTicks = 0
            }
            lastDisplayed = stats.displayedPictures
            lastTime = player.currentTime

            if frozenTicks >= 4 {
                frozenTicks = 0
                await recoverVideoOutput()
            }
        }
    }

    private func recoverVideoOutput() async {
        guard videoRecoveries < 3 else { return }
        videoRecoveries += 1
        isRecoveringVideo = true
        defer { isRecoveringVideo = false }
        #if DEBUG
        playbackLog.notice("video output frozen: rebuilding session (attempt \(videoRecoveries, privacy: .public))")
        #endif

        let externalSubtitle = subs.available.first { $0.id == subs.selectedID }
        do {
            try await player.recast(to: nil)
            if let externalSubtitle { subs.apply(externalSubtitle, on: player) }
        } catch {
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

            guard !upNextCancelled, !didAutoAdvance, failure == nil, !isReconnecting,
                  pendingResume == nil,
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
        guard isActive, !isReconnecting, !isRecoveringVideo, !didFinishPlayback, failure == nil else { return }
        if isNetworkStream, recovery.endedPrematurely(duration: knownDuration) {
            requestReconnect()
            return
        }
        didFinishPlayback = true
        if let progress, knownDuration > .zero {
            WatchProgressStore.shared.record(
                id: progress.mediaID, mediaType: progress.mediaType, title: progress.title,
                posterURL: progress.posterURL, season: progress.season,
                episode: progress.episode, episodeID: progress.episodeID,
                position: knownDuration, duration: knownDuration, source: progress.source)
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
            let stats = player.statistics

            playbackLog.notice("""
            \(stalled ? "STALL" : "ok", privacy: .public) · playing=\(player.isPlaying, privacy: .public) \
            playhead=\(timecode(now), privacy: .public) Δ=\(String(format: "%.2f", delta), privacy: .public)s \
            state=\(String(describing: player.state), privacy: .public) buffering=\(isBuffering, privacy: .public) \
            frames=\(stats?.displayedPictures ?? 0, privacy: .public) late=\(stats?.latePictures ?? 0, privacy: .public) lost=\(stats?.lostPictures ?? 0, privacy: .public)
            """)
        }
    }
    #endif

    private func start() {
        isActive = true
        recovery.position = startAt
        pendingResume = startAt > .zero ? startAt : nil
        player.aspectRatio = settings.fillScreen ? .fill : .default
        player.setSubtitleScale(SubtitleScale(Float(settings.subtitleScale)))
        Task {
            await PlaybackAudioSession.activate()
            guard isActive else { return }
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

                if !isTorrent {
                    media.addOption(":http-reconnect")
                }
            }
            try player.play(media)
        } catch {
            requestReconnect()
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
        guard let progress, !didFinishPlayback, recovery.position > .zero else { return }
        WatchProgressStore.shared.record(
            id: progress.mediaID, mediaType: progress.mediaType, title: progress.title,
            posterURL: progress.posterURL, season: progress.season,
            episode: progress.episode, episodeID: progress.episodeID,
            position: recovery.position,
            duration: knownDuration > .zero ? knownDuration : player.duration, source: progress.source)
    }

    private func teardown() {
        isActive = false
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
    let onRetry: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(message)
                .multilineTextAlignment(.center)
                .font(.callout)
            Button("Retry", action: onRetry)
                .buttonStyle(.borderedProminent)
            Button("Close", action: onClose)
                .buttonStyle(.bordered)
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 18))
    }
}
