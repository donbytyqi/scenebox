//
//  MediaResult.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

nonisolated public struct MediaResult: Identifiable, Sendable {
    public let id: String          // IMDb id, e.g. "tt1375666"
    public let type: MediaType
    public let name: String
    public let year: String?
    public let posterURL: URL?
    public let description: String?
}

extension MediaResult: Hashable {
    public static func == (lhs: MediaResult, rhs: MediaResult) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
