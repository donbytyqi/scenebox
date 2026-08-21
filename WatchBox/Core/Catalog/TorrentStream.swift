//
//  TorrentStream.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

nonisolated public struct TorrentStream: Identifiable, Sendable {
    public let id: String          // infoHash hex
    public let title: String       // full description line from Torrentio
    public let displayName: String // short label (source + resolution)
    public let infoHash: Data
    public let fileIndex: Int?     // which file in the torrent is the video
    public let trackers: [URL]
    public let seeders: Int?
    public let sizeText: String?
    public let resolution: String?
    public let url: URL?

    public var magnet: MagnetLink {
        MagnetLink(infoHash: infoHash, displayName: displayName, trackers: trackers)
    }

    public var isDebrid: Bool { url != nil }
}
