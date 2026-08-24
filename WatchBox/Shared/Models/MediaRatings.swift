//
//  MediaRatings.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation

nonisolated public struct MediaRatings: Sendable, Equatable {
    public var imdb: Double?
    public var rottenTomatoes: Int?
    public var metacritic: Int?

    public var isEmpty: Bool { imdb == nil && rottenTomatoes == nil && metacritic == nil }

    public init(imdb: Double? = nil, rottenTomatoes: Int? = nil, metacritic: Int? = nil) {
        self.imdb = imdb
        self.rottenTomatoes = rottenTomatoes
        self.metacritic = metacritic
    }
}
