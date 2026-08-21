//
//  SubtitleContext.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

nonisolated struct SubtitleContext: Sendable, Equatable {
    let imdbID: String
    let type: MediaType
    let season: Int?
    let episode: Int?
}
