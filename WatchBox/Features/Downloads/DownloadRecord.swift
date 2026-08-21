//
//  DownloadRecord.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import Foundation

struct DownloadRecord: Codable, Identifiable, Sendable, Hashable {
    let id: String              // info-hash hex — also the folder name
    var title: String           // "Inception"
    var releaseName: String     // "YTS 1080p BluRay"
    var mediaID: String         // IMDb id, for navigating back to the detail screen
    var mediaType: String
    var posterURLString: String?
    var episodeLabel: String?   // "S1E3", nil for movies
    var magnetURI: String
    var fileIndex: Int?
    var totalBytes: Int64
    var isComplete: Bool
    var addedAt: Date
    var debridURLString: String?
    var debridFileName: String?
    var localRelativePath: String?

    var posterURL: URL? { posterURLString.flatMap(URL.init(string:)) }
    var magnet: MagnetLink? { MagnetLink(string: magnetURI) }
    var debridURL: URL? { debridURLString.flatMap(URL.init(string:)) }
    var isDebrid: Bool { debridURLString != nil }

    var subtitleLine: String {
        [episodeLabel, releaseName].compactMap { $0 }.joined(separator: " · ")
    }

    var watchProgressContext: WatchProgressContext? {
        guard let type = MediaType(rawValue: mediaType) else { return nil }
        let parts = episodeParts
        return WatchProgressContext(
            mediaID: mediaID, mediaType: type, title: title, posterURL: posterURL,
            season: parts.season, episode: parts.episode, episodeID: parts.id)
    }

    private var episodeParts: (season: Int?, episode: Int?, id: String?) {
        guard let label = episodeLabel else { return (nil, nil, nil) }
        let numbers = label.dropFirst().split(separator: "E").compactMap { Int($0) }
        guard numbers.count == 2 else { return (nil, nil, nil) }
        return (numbers[0], numbers[1], "\(mediaID):\(numbers[0]):\(numbers[1])")
    }

    var subtitleContext: SubtitleContext? {
        guard let type = MediaType(rawValue: mediaType) else { return nil }
        guard type == .series else {
            return SubtitleContext(imdbID: mediaID, type: type, season: nil, episode: nil)
        }
        guard let label = episodeLabel else { return nil }
        let numbers = label.dropFirst()               // strip leading "S"
            .split(separator: "E")
            .compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        return SubtitleContext(imdbID: mediaID, type: type, season: numbers[0], episode: numbers[1])
    }
}
