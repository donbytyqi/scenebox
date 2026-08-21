//
//  DownloadStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import Foundation
import Network
import Observation

@MainActor
@Observable
final class DownloadStore {
    static let shared = DownloadStore()

    private(set) var downloads: [Download] = []
    private(set) var diskUsage: Int64 = 0

    @ObservationIgnored private let root: URL
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var startTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var lastDiskSample = Date.distantPast
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    private(set) var isOnCellular = false
    @ObservationIgnored private var waitingForWiFi: Set<String> = []

    init(settings: AppSettings? = nil) {
        self.settings = settings ?? .shared
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = documents.appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        BackupExclusion.exclude(root)
        load()
        refreshDiskUsage()
        pollTask = Task { await pollForever() }
        startPathMonitor()
    }

    // MARK: - Wi-Fi only

    private func startPathMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let cellular = path.usesInterfaceType(.cellular) && !path.usesInterfaceType(.wifi)
                && !path.usesInterfaceType(.wiredEthernet)
            Task { @MainActor [weak self] in self?.pathChanged(isCellular: cellular || path.isExpensive) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "downloads.path"))
    }

    private func pathChanged(isCellular: Bool) {
        guard isCellular != isOnCellular else { return }
        isOnCellular = isCellular
        guard settings.wifiOnly else { return }
        if isCellular {
            for download in downloads where download.phase.isActive {
                waitingForWiFi.insert(download.id)
                pause(download)
                download.failureMessage = Self.waitingForWiFiMessage
            }
        } else {
            let resume = waitingForWiFi
            waitingForWiFi.removeAll()
            for download in downloads where resume.contains(download.id) {
                download.failureMessage = nil
                self.resume(download)
            }
        }
    }

    private var blockedByWiFiOnly: Bool { settings.wifiOnly && isOnCellular }
    private static let waitingForWiFiMessage = "Waiting for Wi-Fi"

    // MARK: - Library

    var activeCount: Int { downloads.filter { $0.phase.isActive }.count }

    func contains(infoHash: String) -> Bool {
        downloads.contains { $0.id == infoHash.lowercased() }
    }

    func completedDownload(mediaID: String, episodeLabel: String?) -> Download? {
        downloads.first {
            $0.record.mediaID == mediaID
                && $0.record.episodeLabel == episodeLabel
                && ($0.phase == .completed || $0.record.isComplete)
        }
    }

    func isDownloaded(mediaID: String, episodeLabel: String? = nil) -> Bool {
        completedDownload(mediaID: mediaID, episodeLabel: episodeLabel) != nil
    }

    @discardableResult
    func add(stream: TorrentStream, title: String, mediaID: String, mediaType: MediaType,
             posterURL: URL?, episode: Episode? = nil) -> Download {
        let id = stream.id.lowercased()
        if let existing = downloads.first(where: { $0.id == id }) { return existing }

        let record = DownloadRecord(
            id: id,
            title: title,
            releaseName: stream.displayName,
            mediaID: mediaID,
            mediaType: mediaType.rawValue,
            posterURLString: posterURL?.absoluteString,
            episodeLabel: episode?.label,
            magnetURI: stream.isDebrid ? "" : stream.magnet.magnetURI,
            fileIndex: stream.fileIndex,
            totalBytes: stream.isDebrid ? 0 : (stream.sizeText.flatMap(ByteFormat.bytes(fromSizeText:)) ?? 0),
            isComplete: false,
            addedAt: Date(),
            debridURLString: stream.url?.absoluteString,
            debridFileName: stream.url.map { Self.fileName(from: $0, title: title) }
        )
        let download = Download(record: record, phase: .paused)
        downloads.insert(download, at: 0)
        save()
        resume(download)
        if let context = record.subtitleContext {
            let language = settings.preferredSubtitleLanguage
            Task.detached(priority: .utility) {
                await SubtitlesProvider().prefetch(context: context, preferredLanguage: language)
            }
        }
        return download
    }

    func resume(_ download: Download) {
        guard !download.phase.isActive, download.phase != .completed else { return }

        guard hasRoomForMoreDownloads else {
            download.phase = .failed
            download.failureMessage = DownloadError.storageCapReached.errorDescription
            return
        }
        if blockedByWiFiOnly {
            waitingForWiFi.insert(download.id)
            download.phase = .paused
            download.failureMessage = Self.waitingForWiFiMessage
            return
        }
        download.failureMessage = nil

        if download.record.isDebrid {
            resumeDebrid(download)
            return
        }

        guard startTasks[download.id] == nil else { return }

        download.failureMessage = nil
        download.phase = .resolving

        startTasks[download.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.startTasks[download.id] = nil }
            do {
                let session = try await self.makeSession(for: download)
                guard download.phase == .resolving else {
                    await session.stop()      // paused while we were resolving
                    return
                }
                download.session = session
                download.phase = .downloading
                await session.startDownload()
            } catch {
                download.phase = .failed
                download.failureMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Debrid (direct HTTP) downloads

    private func resumeDebrid(_ download: Download) {
        guard download.debridDownloader == nil else { return }
        guard let url = download.record.debridURL else {
            download.phase = .failed
            download.failureMessage = "This release has no debrid link."
            return
        }
        download.failureMessage = nil
        download.phase = .downloading
        download.rateSample = (download.downloadedBytes, Date())

        let id = download.id
        let downloader = DebridDownloader(
            destination: debridFileURL(for: download.record),
            onProgress: { progress in
                Task { @MainActor [weak self] in self?.applyDebridProgress(id: id, progress: progress) }
            },
            onComplete: { result in
                Task { @MainActor [weak self] in self?.finishDebrid(id: id, result: result) }
            })
        download.debridDownloader = downloader
        downloader.start(url: url)
    }

    private func applyDebridProgress(id: String, progress: DebridDownloader.Progress) {
        guard let download = downloads.first(where: { $0.id == id }), download.phase == .downloading else { return }
        download.downloadedBytes = progress.downloadedBytes
        if progress.totalBytes > 0, download.record.totalBytes == 0 {
            download.record.totalBytes = progress.totalBytes
            save()
        }
        let total = download.record.totalBytes
        download.progress = total > 0 ? min(1, Double(progress.downloadedBytes) / Double(total)) : 0

        let now = Date()
        if let sample = download.rateSample, now.timeIntervalSince(sample.at) >= 0.5 {
            let dt = now.timeIntervalSince(sample.at)
            let instant = Double(progress.downloadedBytes - sample.bytes) / dt
            download.downloadRate = 0.5 * download.downloadRate + 0.5 * max(0, instant)
            download.rateSample = (progress.downloadedBytes, now)
        }
    }

    private func finishDebrid(id: String, result: Result<URL, Error>) {
        guard let download = downloads.first(where: { $0.id == id }) else { return }
        download.debridDownloader = nil
        switch result {
        case .success:
            download.phase = .completed
            download.progress = 1
            download.downloadRate = 0
            download.record.isComplete = true
            if download.record.totalBytes == 0 { download.record.totalBytes = download.downloadedBytes }
            save()
        case .failure(let error):
            download.phase = .failed
            download.failureMessage = error.localizedDescription
        }
    }

    private func debridFileURL(for record: DownloadRecord) -> URL {
        folder(for: record.id).appendingPathComponent(record.debridFileName ?? "video.mp4")
    }

    private static func fileName(from url: URL, title: String) -> String {
        let last = url.lastPathComponent
        if !last.isEmpty, (last as NSString).pathExtension.isEmpty == false { return last }
        return title.replacingOccurrences(of: "/", with: "-") + ".mp4"
    }

    // MARK: - Lifecycle

    func pause(_ download: Download) {
        waitingForWiFi.remove(download.id)
        download.failureMessage = nil
        if download.record.isDebrid {
            download.debridDownloader?.cancel()
            download.debridDownloader = nil
            download.phase = .paused
            return
        }

        startTasks[download.id]?.cancel()
        startTasks[download.id] = nil
        download.phase = .paused

        let session = download.session
        download.session = nil
        Task { await session?.stop() }
    }

    func remove(_ download: Download) {
        waitingForWiFi.remove(download.id)
        download.debridDownloader?.cancel()
        download.debridDownloader = nil
        startTasks[download.id]?.cancel()
        startTasks[download.id] = nil

        let session = download.session
        download.session = nil
        let directory = folder(for: download.id)
        Task { [weak self] in
            await session?.stop()
            await session?.waitForTeardown()   // don't delete under the engine
            try? FileManager.default.removeItem(at: directory)
            self?.refreshDiskUsage()
        }

        downloads.removeAll { $0.id == download.id }
        save()
    }

    func localFileURL(for download: Download) async -> URL? {
        guard download.phase == .completed else { return nil }
        if download.record.isDebrid {
            let url = debridFileURL(for: download.record)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let relative = download.record.localRelativePath {
            let url = folder(for: download.id).appendingPathComponent(relative)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        if let session = download.session {
            let url = await session.localFileURL()
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
        return nil
    }

    // MARK: - Storage accounting

    func refreshDiskUsage() {
        lastDiskSample = Date()
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.totalFileAllocatedSizeKey], options: []
        ) else { diskUsage = 0; return }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let allocated = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize
            total += Int64(allocated ?? 0)
        }
        diskUsage = total
    }

    var hasRoomForMoreDownloads: Bool {
        settings.storageCapBytes <= 0 || diskUsage < settings.storageCapBytes
    }

    func removeAll() {
        for download in downloads {
            startTasks[download.id]?.cancel()
            let session = download.session
            download.session = nil
            Task { await session?.stop() }
        }
        startTasks.removeAll()
        downloads.removeAll()
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        save()
        refreshDiskUsage()
    }

    // MARK: - Sessions

    private func folder(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    private func makeSession(for download: Download) async throws -> LibtorrentSession {
        let directory = folder(for: download.id)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let magnet = download.record.magnet else { throw DownloadError.badMagnet }
        return try await LibtorrentSession.resolve(
            magnet: magnet, downloadDirectory: directory,
            preferredFileIndex: download.record.fileIndex,
            maxPeers: settings.maxPeers, extraTrackers: settings.customTrackerURLs)
    }

    // MARK: - Polling

    private func pollForever() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }

            var needsSave = false
            for download in downloads where download.phase == .downloading {
                guard let session = download.session else { continue }
                let stats = await session.currentStats()

                if download.record.totalBytes == 0 {
                    download.record.totalBytes = await session.streamFileLength()
                    needsSave = true
                }
                if download.record.localRelativePath == nil {
                    download.record.localRelativePath = await session.localRelativePath()
                    needsSave = true
                }

                download.downloadedBytes = stats.downloadedBytes
                download.downloadRate = stats.downloadRate
                download.connectedPeers = stats.connectedPeers

                download.progress = stats.progress

                if stats.isComplete {
                    download.phase = .completed
                    download.progress = 1
                    download.record.isComplete = true
                    download.session = nil
                    needsSave = true
                    Task { await session.stop() }
                }
            }
            if needsSave { save() }

            if downloads.contains(where: { $0.phase.isActive }),
               Date().timeIntervalSince(lastDiskSample) >= 2 {
                refreshDiskUsage()
            }
        }
    }

    // MARK: - Persistence

    private var indexURL: URL { root.appendingPathComponent("index.json") }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data)
        else { return }

        downloads = records.map { Download(record: $0, phase: $0.isComplete ? .completed : .paused) }
    }

    private func save() {
        let records = downloads.map(\.record)
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }
}
