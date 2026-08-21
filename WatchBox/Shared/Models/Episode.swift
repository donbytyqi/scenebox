//
//  Episode.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

nonisolated public struct Episode: Identifiable, Sendable, Hashable {
    public let id: String          // "tt1520211:1:3"
    public let season: Int
    public let episode: Int
    public let name: String
    public let overview: String?
    public let thumbnailURL: URL?
    public let released: Date?

    public var label: String { "S\(season)E\(episode)" }
}
