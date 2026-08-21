//
//  Download.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class Download: Identifiable {
    var record: DownloadRecord
    var id: String { record.id }

    var phase: Phase = .paused
    var progress: Double = 0
    var downloadedBytes: Int64 = 0
    var downloadRate: Double = 0
    var connectedPeers: Int = 0
    var failureMessage: String?

    @ObservationIgnored var session: LibtorrentSession?
    @ObservationIgnored var debridDownloader: DebridDownloader?
    @ObservationIgnored var rateSample: (bytes: Int64, at: Date)?

    init(record: DownloadRecord, phase: Phase) {
        self.record = record
        self.phase = phase
        if phase == .completed { progress = 1 }
    }

    enum Phase: Equatable {
        case resolving
        case downloading
        case paused
        case completed
        case failed

        var isActive: Bool { self == .resolving || self == .downloading }
    }

    var statusText: String {
        switch phase {
        case .resolving: "Fetching metadata…"
        case .downloading:
            if record.isDebrid {
                "Debrid · \(ByteFormat.rate(downloadRate))"
            } else {
                connectedPeers == 0
                    ? "Looking for peers…"
                    : "\(connectedPeers) peers · \(ByteFormat.rate(downloadRate))"
            }
        case .paused:
            if let failureMessage { failureMessage }   // e.g. "Waiting for Wi-Fi"
            else { progress > 0 ? "Paused · \(ByteFormat.percentDetailed(progress))" : "Paused" }
        case .completed: ByteFormat.size(record.totalBytes)
        case .failed: failureMessage ?? "Failed"
        }
    }

    var sizeProgressText: String? {
        guard record.totalBytes > 0, phase != .completed else { return nil }
        let done = record.isDebrid
            ? min(max(downloadedBytes, 0), record.totalBytes)
            : Int64(min(max(progress, 0), 1) * Double(record.totalBytes))
        return "\(ByteFormat.size(done)) / \(ByteFormat.size(record.totalBytes)) · \(ByteFormat.percentDetailed(progress))"
    }
}
