//
//  LibtorrentSession.swift
//  SceneBox
//
//  Created by SpontaneousArray on 04.08.26.
//

import Foundation
#if DEBUG
import OSLog
#endif

actor LibtorrentSession {
    typealias Stats = SwarmStats

    private let engine: TorrentEngine
    private let saveDirectory: URL
    private let preferredFileIndex: Int?
    private let waiters = PieceWaiterRegistry()

    private var streamFile: TKFile?
    private var server: LibtorrentStreamServer?
    private var teardown: Task<Void, Never>?

    private var resumeURL: URL { saveDirectory.appendingPathComponent(".ltresume", isDirectory: false) }

    private init(saveDirectory: URL, maxPeers: Int, extraTrackers: [URL], preferredFileIndex: Int?) {
        self.saveDirectory = saveDirectory
        self.preferredFileIndex = preferredFileIndex
        let trackers = extraTrackers + DefaultTrackers.list
        self.engine = TorrentEngine(saveDirectory: saveDirectory.path,
                                    maxPeers: maxPeers,
                                    extraTrackers: trackers.map(\.absoluteString))
    }

    static func resolve(magnet: MagnetLink, downloadDirectory: URL, preferredFileIndex: Int? = nil,
                        timeout: TimeInterval = 40, maxPeers: Int = 80,
                        extraTrackers: [URL] = []) async throws -> LibtorrentSession {
        let session = LibtorrentSession(saveDirectory: downloadDirectory, maxPeers: maxPeers,
                                        extraTrackers: extraTrackers, preferredFileIndex: preferredFileIndex)
        try await session.begin(magnet: magnet, timeout: timeout)
        return session
    }

    private func begin(magnet: MagnetLink, timeout: TimeInterval) async throws {
        engine.onPieceFinished = { [waiters] index in waiters.fulfill(Int(index)) }
        let resume = try? Data(contentsOf: resumeURL)
        engine.startMagnet(magnet.magnetURI, resumeData: resume)
        guard engine.isActive else { throw TorrentEngineError.failedToStart }
        #if DEBUG
        await TorrentDiagnostics.shared.begin(engine: engine, infoHash: magnet.infoHash.hexString)
        #endif

        let deadline = Date().addingTimeInterval(timeout)
        var lastDiscoveryRetry = Date()
        while !engine.hasMetadata {
            try await Task.sleep(for: .milliseconds(200))
            if Date().timeIntervalSince(lastDiscoveryRetry) >= 15 {
                engine.retryMetadataDiscovery()
                lastDiscoveryRetry = Date()
            }
            #if DEBUG
            if Int(Date().timeIntervalSince1970 * 5) % 5 == 0 {
                let s = engine.stats()
                let peers = s.numPeers, seeds = s.numSeeds
                torrentLog.notice("resolving: peers=\(peers, privacy: .public) seeds=\(seeds, privacy: .public)")
            }
            #endif
            if Date() > deadline { throw TorrentEngineError.metadataTimeout }
        }
        try selectStreamFile()
    }

    private func selectStreamFile() throws {
        let files = engine.files()
        guard !files.isEmpty else { throw TorrentEngineError.noPlayableFile }
        let chosen: TKFile
        if let index = preferredFileIndex, index >= 0, index < files.count {
            chosen = files[index]
        } else {
            chosen = files.max(by: { $0.length < $1.length }) ?? files[0]
        }
        streamFile = chosen
        engine.selectFile(chosen.index)
    }

    func startStreaming(port: UInt16 = 8888, resumeFraction: Double? = nil) async throws -> URL {
        guard let file = streamFile else { throw TorrentEngineError.noPlayableFile }
        engine.prepareStreaming(forFile: file.index)
        let server = LibtorrentStreamServer(engine: engine, filePath: file.path,
                                            fileOffset: file.offset, fileLength: file.length,
                                            waiters: waiters, pieceLength: engine.pieceLength, port: port)
        await server.primeHeadAndTail()
        if let fraction = resumeFraction, fraction > 0, fraction < 1 {
            await server.updatePlayhead(absoluteOffset: file.offset + Int64(Double(file.length) * fraction))
        } else {
            await server.updatePlayhead(absoluteOffset: file.offset)
        }
        let url = try await server.start()
        self.server = server
        return url
    }

    func initialBufferProgress(headBytes: Int64, tailBytes: Int64) async -> Double {
        guard let file = streamFile else { return 0 }
        let pieceLength = Int64(engine.pieceLength)
        guard pieceLength > 0 else { return 0 }
        let fileEnd = file.offset + file.length - 1
        let headEnd = min(file.offset + max(0, headBytes) - 1, fileEnd)
        let tailStart = max(file.offset, fileEnd + 1 - tailBytes)

        var wanted = 0, have = 0
        func tally(_ from: Int64, _ through: Int64) {
            guard through >= from else { return }
            for piece in Int(from / pieceLength)...Int(through / pieceLength) {
                wanted += 1
                if engine.hasPiece(piece) { have += 1 }
            }
        }
        tally(file.offset, headEnd)
        tally(tailStart, fileEnd)
        return wanted == 0 ? 1 : Double(have) / Double(wanted)
    }

    func headReadable(headBytes: Int64) async -> Bool {
        guard let server else { return false }
        return server.headReadable(headBytes: headBytes)
    }

    func endPrebuffer() async {
        guard let file = streamFile else { return }
        engine.beginStreamingSteadyState(forFile: file.index)
    }

    // MARK: Download mode (no stream server)

    func startDownload() async { engine.resume() }

    func streamFileLength() async -> Int64 { streamFile?.length ?? 0 }

    func localFileURL() async -> URL { URL(fileURLWithPath: streamFile?.path ?? "") }

    func localRelativePath() async -> String? {
        guard let path = streamFile?.path else { return nil }
        let base = saveDirectory.path
        guard path.hasPrefix(base) else { return (path as NSString).lastPathComponent }
        var relative = String(path.dropFirst(base.count))
        while relative.hasPrefix("/") { relative.removeFirst() }
        return relative
    }

    func currentStats() async -> Stats {
        let snapshot = engine.stats()
        var stats = Stats()
        stats.downloadRate = snapshot.downloadRate
        stats.connectedPeers = snapshot.numPeers
        stats.progress = snapshot.progress
        stats.downloadedBytes = snapshot.downloadedBytes
        stats.isComplete = snapshot.progress >= 1.0
        return stats
    }

    func stop() async {
        #if DEBUG
        await TorrentDiagnostics.shared.end()
        #endif
        if let server { await server.stop() }
        server = nil
        waiters.fulfillAll()
        let engine = self.engine
        let resumeURL = self.resumeURL
        teardown = Task.detached {
            if let data = await engine.resumeData() { try? data.write(to: resumeURL) }
            engine.stop()
        }
    }

    func waitForTeardown() async {
        await teardown?.value
    }
}
