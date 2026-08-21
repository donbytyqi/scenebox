//
//  StreamCoordinator.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation
import Observation
#if DEBUG
import OSLog
#endif

@MainActor
@Observable
final class StreamCoordinator {
    struct Target: Identifiable, Equatable {
        let url: URL
        let title: String
        let showsTorrentStats: Bool
        var subtitleContext: SubtitleContext?
        var startPosition: Duration = .zero
        var progress: WatchProgressContext?
        var originalAudioLanguage: String?

        var id: URL { url }
    }

    private(set) var isPresenting = false
    private(set) var target: Target?
    private(set) var preparing: String?
    private(set) var bufferProgress: Double?
    private(set) var errorMessage: String?

    private(set) var title = ""
    private(set) var backdropURL: URL?
    private(set) var logoURL: URL?

    private(set) var episodePlaylist: EpisodePlaylist?

    private(set) var stats = SwarmStats()

    @ObservationIgnored private var session: LibtorrentSession?
    @ObservationIgnored private var prepareTask: Task<Void, Never>?
    @ObservationIgnored private var statsTask: Task<Void, Never>?
    @ObservationIgnored private var streamDirectory: URL?
    @ObservationIgnored private let settings: AppSettings

    static var streamCacheRoot: URL { StreamCache.root }

    static func pruneCacheAtLaunch() {
        StreamCache.removeLegacyLocation()
        let limit = AppSettings.shared.streamCacheLimitBytes
        limit > 0 ? StreamCache.prune(toBytes: limit) : StreamCache.clear()
    }

    static func purgeStreamCache() { StreamCache.clear() }

    init(settings: AppSettings? = nil) {
        self.settings = settings ?? .shared
    }

    deinit {
        prepareTask?.cancel()
        statsTask?.cancel()
    }

    var isPreparing: Bool { preparing != nil }

    var preparingStatus: String? {
        if let preparing { return preparing }
        guard bufferProgress != nil, errorMessage == nil else { return nil }
        guard stats.connectedPeers > 0 else { return "Connecting to sources…" }
        return "\(stats.connectedPeers) source\(stats.connectedPeers == 1 ? "" : "s") · \(ByteFormat.rate(stats.downloadRate))"
    }

    func play(_ stream: TorrentStream, title: String, backdropURL: URL?, logoURL: URL? = nil,
              subtitleContext: SubtitleContext? = nil, episodes: EpisodePlaylist? = nil,
              startAt: Duration = .zero, resumeFraction: Double? = nil,
              progress: WatchProgressContext? = nil,
              originalAudioLanguage: String? = nil,
              fallbacks: [TorrentStream] = []) {
        episodePlaylist = episodes
        prepareTask?.cancel()
        let previousSession = session
        let previousDirectory = streamDirectory
        session = nil
        streamDirectory = nil

        self.title = title
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.errorMessage = nil
        self.target = nil
        self.stats = SwarmStats()
        self.preparing = "Fetching sources from peers…"
        self.bufferProgress = nil
        self.isPresenting = true

        prepareTask = Task { [settings] in
            await previousSession?.stop()
            let cacheLimit = settings.streamCacheLimitBytes
            let directory = Self.streamCacheRoot
                .appendingPathComponent(stream.id, isDirectory: true)
            if cacheLimit <= 0 || previousDirectory == directory {
                await previousSession?.waitForTeardown()
            }
            if cacheLimit <= 0, let previousDirectory {
                try? FileManager.default.removeItem(at: previousDirectory)
            }
            guard !Task.isCancelled else { return }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                self.streamDirectory = directory
                if cacheLimit > 0 { StreamCache.prune(toBytes: cacheLimit, keeping: [stream.id]) }

                let session = try await LibtorrentSession.resolve(
                    magnet: stream.magnet,
                    downloadDirectory: directory,
                    preferredFileIndex: stream.fileIndex,
                    maxPeers: settings.maxPeers,
                    extraTrackers: settings.customTrackerURLs)
                guard !Task.isCancelled else { await session.stop(); return }
                self.session = session

                preparing = "Starting stream…"
                let url = try await session.startStreaming(port: UInt16(settings.streamingPort),
                                                           resumeFraction: resumeFraction)
                guard !Task.isCancelled else { await session.stop(); return }

                let started = Date()
                preparing = nil
                var headReady = 0.0
                var lastBytes: Int64 = 0
                var lastProgressAt = Date()
                let headBytes: Int64 = 16 * 1024 * 1024
                var headVerifiedAt: Date?
                var steadyStateStarted = false
                while !Task.isCancelled {
                    headReady = await session.initialBufferProgress(
                        headBytes: headBytes, tailBytes: 0)
                    let stats = await session.currentStats()
                    self.stats = stats
                    bufferProgress = headReady
                    if stats.downloadedBytes > lastBytes {
                        lastBytes = stats.downloadedBytes
                        lastProgressAt = Date()
                    }
                    let elapsed = Date().timeIntervalSince(started)
                    let stalledFor = Date().timeIntervalSince(lastProgressAt)
                    #if DEBUG
                    if Int(elapsed * 3.3) % 3 == 0 {   // ~1 line/sec of the 300ms loop
                        let readable = await session.headReadable(headBytes: headBytes)
                        torrentLog.notice("gate: elapsed=\(Int(elapsed), privacy: .public)s headReady=\(String(format: "%.2f", headReady), privacy: .public) readable=\(readable, privacy: .public) done=\(stats.downloadedBytes / 1_048_576, privacy: .public)MB stalledFor=\(Int(stalledFor), privacy: .public)s")
                    }
                    #endif
                    if headReady >= 1 {
                        if !steadyStateStarted {
                            steadyStateStarted = true
                            await session.endPrebuffer()
                        }
                        if await session.headReadable(headBytes: headBytes) { break }
                        let verifiedAt = headVerifiedAt ?? Date()
                        headVerifiedAt = verifiedAt
                        if Date().timeIntervalSince(verifiedAt) > 6 { break }
                    }
                    if elapsed > 300 { break }                   // absolute ceiling: 5 min
                    if lastBytes == 0 {
                        if elapsed > 120 && stats.connectedPeers == 0 { break }
                    } else if stalledFor > 90 {
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(300))
                }
                guard !Task.isCancelled else { await session.stop(); return }
                if headReady <= 0 {
                    await session.stop()
                    self.session = nil
                    throw TorrentEngineError.bufferTimeout
                }
                await session.endPrebuffer()

                target = Target(url: url, title: title, showsTorrentStats: true,
                                subtitleContext: subtitleContext,
                                startPosition: startAt, progress: progress,
                                originalAudioLanguage: originalAudioLanguage)
                preparing = nil
                pollStats(from: session)
            } catch {
                guard !Task.isCancelled else { return }
                if let engineError = error as? TorrentEngineError,
                   engineError == .metadataTimeout || engineError == .bufferTimeout,
                   let next = fallbacks.first {
                    preparing = "Source unresponsive — trying another…"
                    Task { @MainActor [self] in
                        play(next, title: title, backdropURL: backdropURL, logoURL: logoURL,
                             subtitleContext: subtitleContext, episodes: episodes,
                             startAt: startAt, resumeFraction: resumeFraction,
                             progress: progress, originalAudioLanguage: originalAudioLanguage,
                             fallbacks: Array(fallbacks.dropFirst()))
                    }
                    return
                }
                preparing = nil
                errorMessage = friendlyError(error)
            }
        }
    }

    func playDebrid(url: URL, title: String, backdropURL: URL?, logoURL: URL? = nil,
                    subtitleContext: SubtitleContext? = nil, episodes: EpisodePlaylist? = nil,
                    startAt: Duration = .zero, progress: WatchProgressContext? = nil,
                    originalAudioLanguage: String? = nil) {
        episodePlaylist = episodes
        prepareTask?.cancel()
        self.title = title
        self.backdropURL = backdropURL
        self.logoURL = logoURL
        self.errorMessage = nil
        self.preparing = nil
        self.stats = SwarmStats()
        self.isPresenting = true
        self.target = Target(url: url, title: title, showsTorrentStats: false,
                             subtitleContext: subtitleContext,
                             startPosition: startAt, progress: progress,
                             originalAudioLanguage: originalAudioLanguage)
    }

    func playLocalFile(at url: URL, title: String, subtitleContext: SubtitleContext? = nil,
                       startAt: Duration = .zero, progress: WatchProgressContext? = nil,
                       originalAudioLanguage: String? = nil) {
        episodePlaylist = nil
        self.title = title
        self.backdropURL = nil
        self.logoURL = nil
        self.errorMessage = nil
        self.preparing = nil
        self.isPresenting = true
        self.target = Target(url: url, title: title, showsTorrentStats: false,
                             subtitleContext: subtitleContext,
                             startPosition: startAt, progress: progress,
                             originalAudioLanguage: originalAudioLanguage)
    }

    func stop() {
        prepareTask?.cancel(); prepareTask = nil
        statsTask?.cancel(); statsTask = nil
        preparing = nil
        bufferProgress = nil
        errorMessage = nil
        target = nil
        backdropURL = nil
        logoURL = nil
        episodePlaylist = nil
        isPresenting = false
        stats = SwarmStats()

        let finished = session
        let directory = streamDirectory
        let cacheLimit = settings.streamCacheLimitBytes
        session = nil
        streamDirectory = nil
        Task {
            await finished?.stop()
            if cacheLimit <= 0 {
                await finished?.waitForTeardown()   // don't delete under the engine
                if let directory { try? FileManager.default.removeItem(at: directory) }
            } else {
                StreamCache.prune(toBytes: cacheLimit)
            }
        }
    }

    private func pollStats(from session: LibtorrentSession) {
        statsTask?.cancel()
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                let current = await session.currentStats()
                guard !Task.isCancelled, let self else { return }
                self.stats = current
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func friendlyError(_ error: Error) -> String {
        if let engineError = error as? TorrentEngineError {
            switch engineError {
            case .failedToStart:
                return "This torrent link could not be started. Try a different source."
            case .metadataTimeout:
                return "Couldn’t reach enough peers for this release. Try a different source; one with more seeders usually connects faster."
            case .noPlayableFile:
                return "This release has no playable video file."
            case .bufferTimeout:
                return "This release isn’t serving data — no seeders reachable right now. Try another source with more seeders."
            }
        }
        return error.localizedDescription
    }
}
