//
//  SwarmStats.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import Foundation

nonisolated struct SwarmStats: Sendable {
    var downloadedBytes: Int64 = 0
    var downloadRate: Double = 0
    var connectedPeers: Int = 0
    var progress: Double = 0
    var isComplete: Bool = false
    var uploadedBytes: Int64 = 0

    init() {}
}
