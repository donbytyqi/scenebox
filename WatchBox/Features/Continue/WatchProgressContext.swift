//
//  WatchProgressContext.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation

nonisolated struct WatchProgressContext: Sendable, Equatable {
    let mediaID: String
    let mediaType: MediaType
    let title: String
    let posterURL: URL?
    let season: Int?
    let episode: Int?
    let episodeID: String?
}
