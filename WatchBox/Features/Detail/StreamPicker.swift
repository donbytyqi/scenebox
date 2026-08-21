//
//  StreamPicker.swift
//  SceneBox
//
//  Created by SpontaneousArray on 04.08.26.
//

import Foundation

enum StreamPicker {
    static func best(from streams: [TorrentStream],
                     preferredResolution: String,
                     debridEnabled: Bool) -> TorrentStream? {
        let wanted = preferredResolution.lowercased()
        return streams.max { a, b in
            rank(a, wanted, debridEnabled) < rank(b, wanted, debridEnabled)
        }
    }

    private static func rank(_ s: TorrentStream, _ wanted: String, _ debrid: Bool) -> (Int, Int, Int) {
        let cached = (debrid && s.isDebrid) ? 1 : 0
        let seeders = s.seeders ?? 0
        let resMatch = (s.resolution?.lowercased() == wanted && seeders >= 5) ? 1 : 0
        return (cached, resMatch, seeders)
    }
}
