//
//  CastMember.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import Foundation

nonisolated public struct CastMember: Identifiable, Sendable, Hashable {
    public let id: Int          // TMDB person id
    public let name: String
    public let role: String?    // character played
    public let photoURL: URL?
}
