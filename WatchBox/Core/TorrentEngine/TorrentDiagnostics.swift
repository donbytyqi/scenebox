//
//  TorrentDiagnostics.swift
//  SceneBox
//
//  Created by SpontaneousArray on 04.08.26.
//

import Foundation
import Network
import OSLog
#if canImport(UIKit)
import UIKit
#endif

nonisolated final class PlayheadTelemetry: @unchecked Sendable {
    static let shared = PlayheadTelemetry()
    private let lock = NSLock()
    private var streamPlayheadMB = -1
    private var window = "-"
    private var playerSeconds = -1.0

    func noteStream(playheadByte: Int64, window: ClosedRange<Int>) {
        lock.lock()
        streamPlayheadMB = Int(playheadByte / 1_048_576)
        self.window = "\(window.lowerBound)…\(window.upperBound)"
        lock.unlock()
    }

    func notePlayerTime(seconds: Double) {
        lock.lock()
        playerSeconds = seconds
        lock.unlock()
    }

    func reset() {
        lock.lock()
        streamPlayheadMB = -1
        window = "-"
        playerSeconds = -1
        lock.unlock()
    }

    func snapshot() -> (playheadMB: Int, window: String, playerSeconds: Double) {
        lock.lock()
        defer { lock.unlock() }
        return (streamPlayheadMB, window, playerSeconds)
    }
}

@MainActor
@Observable
final class TorrentDiagnostics {
    static let shared = TorrentDiagnostics()

    struct Snapshot: Sendable {
        var time = ""
        var appState = "?"
        var deviceLocked = false
        var thermal = ""
        var lowPower = false
        var network = "?"
        var expensive = false
        var constrained = false
        var infoHash = ""
        var torrentState = ""
        var peers = 0, seeds = 0, connections = 0
        var candidates = 0, listPeers = 0, listSeeds = 0
        var downloadRate = 0.0, uploadRate = 0.0
        var wanted: Int64 = 0, wantedDone: Int64 = 0, allTimeDownload: Int64 = 0
        var attempts: Int64 = 0, incoming: Int64 = 0, connectFailures: Int64 = 0
        var dhtNodes = 0
        var disconnectReasons: [String: Int] = [:]
        var lastPeerSource = ""
        var playheadMB = -1
        var window = "-"
        var playerSeconds = -1.0
    }

    private(set) var latest: Snapshot?

    @ObservationIgnored private weak var engine: TorrentEngine?
    @ObservationIgnored private var infoHash = ""
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var fileHandle: FileHandle?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()

    static var metricsFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("diagnostics/metrics.jsonl")
    }

    private init() {
        pathMonitor.start(queue: DispatchQueue(label: "watchbox.diag.path"))
    }

    func begin(engine: TorrentEngine, infoHash: String) {
        end()
        self.engine = engine
        self.infoHash = infoHash
        PlayheadTelemetry.shared.reset()
        openLogFile()
        appendLine(["event": "begin", "infoHash": infoHash,
                    "time": Self.timestamp(), "build": "diag1"])
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func end() {
        tickTask?.cancel()
        tickTask = nil
        engine = nil
        try? fileHandle?.close()
        fileHandle = nil
    }

    private func tick() async {
        guard let engine else { end(); return }
        let diag = await Task.detached { engine.diagnostics() }.value
        var s = Snapshot()
        s.time = Self.timestamp()
        #if canImport(UIKit)
        switch UIApplication.shared.applicationState {
        case .active: s.appState = "active"
        case .inactive: s.appState = "inactive"
        case .background: s.appState = "background"
        @unknown default: s.appState = "unknown"
        }
        s.deviceLocked = !UIApplication.shared.isProtectedDataAvailable
        #endif
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: s.thermal = "nominal"
        case .fair: s.thermal = "fair"
        case .serious: s.thermal = "serious"
        case .critical: s.thermal = "critical"
        @unknown default: s.thermal = "?"
        }
        s.lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let path = pathMonitor.currentPath
        if path.usesInterfaceType(.wifi) { s.network = "wifi" }
        else if path.usesInterfaceType(.cellular) { s.network = "cellular" }
        else if path.usesInterfaceType(.wiredEthernet) { s.network = "wired" }
        else { s.network = path.status == .satisfied ? "other" : "none" }
        s.expensive = path.isExpensive
        s.constrained = path.isConstrained

        s.infoHash = infoHash
        s.torrentState = diag.torrentState
        s.peers = diag.numPeers
        s.seeds = diag.numSeeds
        s.connections = diag.numConnections
        s.candidates = diag.connectCandidates
        s.listPeers = diag.listPeers
        s.listSeeds = diag.listSeeds
        s.downloadRate = diag.downloadRate
        s.uploadRate = diag.uploadRate
        s.wanted = diag.totalWanted
        s.wantedDone = diag.totalWantedDone
        s.allTimeDownload = diag.allTimeDownload
        s.attempts = diag.outgoingAttempts
        s.incoming = diag.incomingAccepts
        s.connectFailures = diag.connectFailures
        s.dhtNodes = diag.dhtNodes
        s.disconnectReasons = diag.disconnectReasons.mapValues(\.intValue)
        s.lastPeerSource = diag.lastPeerSource
        let playhead = PlayheadTelemetry.shared.snapshot()
        s.playheadMB = playhead.playheadMB
        s.window = playhead.window
        s.playerSeconds = playhead.playerSeconds

        latest = s
        persist(s)
    }

    private func persist(_ s: Snapshot) {
        let reasons = s.disconnectReasons.sorted { $0.value > $1.value }
        var line: [String: Any] = [
            "time": s.time, "app": s.appState, "locked": s.deviceLocked,
            "thermal": s.thermal, "lowPower": s.lowPower,
            "net": s.network, "expensive": s.expensive, "constrained": s.constrained,
            "state": s.torrentState, "peers": s.peers, "seeds": s.seeds,
            "conns": s.connections, "candidates": s.candidates,
            "listPeers": s.listPeers, "listSeeds": s.listSeeds,
            "rate": Int(s.downloadRate), "upRate": Int(s.uploadRate),
            "wantedMB": Int(s.wanted / 1_048_576), "doneMB": Int(s.wantedDone / 1_048_576),
            "allTimeMB": Int(s.allTimeDownload / 1_048_576),
            "attempts": s.attempts, "incoming": s.incoming, "connectFail": s.connectFailures,
            "dhtNodes": s.dhtNodes, "src": s.lastPeerSource,
            "playheadMB": s.playheadMB, "window": s.window,
            "playerSec": Int(s.playerSeconds),
        ]
        line["reasons"] = Dictionary(uniqueKeysWithValues: reasons.prefix(8).map { ($0.key, $0.value) })
        appendLine(line)

        let topReason = reasons.first.map { "\($0.key)×\($0.value)" } ?? "-"
        torrentLog.notice("""
        diag: app=\(s.appState, privacy: .public)\(s.deviceLocked ? "/LOCKED" : "", privacy: .public) \
        net=\(s.network, privacy: .public) state=\(s.torrentState, privacy: .public) \
        peers=\(s.peers, privacy: .public) seeds=\(s.seeds, privacy: .public) \
        conns=\(s.connections, privacy: .public) cand=\(s.candidates, privacy: .public) \
        list=\(s.listPeers, privacy: .public) rate=\(Int(s.downloadRate) / 1024, privacy: .public)KB/s \
        att=\(s.attempts, privacy: .public) fail=\(s.connectFailures, privacy: .public) \
        dht=\(s.dhtNodes, privacy: .public) top=\(topReason, privacy: .public)
        """)
    }

    private func openLogFile() {
        let url = Self.metricsFileURL
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64, size > 5_242_880 {
            let prev = url.deletingLastPathComponent().appendingPathComponent("metrics.prev.jsonl")
            try? fm.removeItem(at: prev)
            try? fm.moveItem(at: url, to: prev)
        }
        if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
        fileHandle = try? FileHandle(forWritingTo: url)
        _ = try? fileHandle?.seekToEnd()
    }

    private func appendLine(_ object: [String: Any]) {
        guard let fileHandle,
              var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        try? fileHandle.write(contentsOf: data)
    }

    private static func timestamp() -> String {
        Date().formatted(.iso8601.time(includingFractionalSeconds: true))
    }
}
