//
//  SubtitlesProvider.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import Foundation
import CryptoKit

actor SubtitlesProvider {
    private let base = "https://opensubtitles-v3.strem.io"

    func subtitles(imdbID: String, type: MediaType, season: Int?, episode: Int?) async -> [SubtitleTrack] {
        var id = imdbID
        if type == .series, let season, let episode { id += ":\(season):\(episode)" }
        guard let url = URL(string: "\(base)/subtitles/\(type.rawValue)/\(id).json") else { return [] }

        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let listCache = Self.directory.appendingPathComponent("list-\(Self.digest(id)).json")
        let data: Data
        if let fetched = try? await URLSession.shared.data(for: request).0 {
            data = fetched
            try? FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
            try? fetched.write(to: listCache, options: .atomic)
        } else if let cached = try? Data(contentsOf: listCache) {
            data = cached
        } else {
            return []
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = json["subtitles"] as? [[String: Any]]
        else { return [] }

        var seen = Set<String>()
        var out: [SubtitleTrack] = []
        for item in raw {
            guard let urlString = item["url"] as? String, let url = URL(string: urlString),
                  let lang = item["lang"] as? String else { continue }
            let identifier = (item["id"] as? String) ?? urlString
            guard seen.insert(identifier).inserted else { continue }
            out.append(SubtitleTrack(id: identifier, languageCode: lang, url: url))
        }
        return out.sorted { rank($0.languageCode) < rank($1.languageCode) }
    }

    func prefetch(context: SubtitleContext, preferredLanguage: String) async {
        guard !preferredLanguage.isEmpty else { return }
        let tracks = await subtitles(imdbID: context.imdbID, type: context.type,
                                     season: context.season, episode: context.episode)
        guard let match = tracks.first(where: { $0.languageCode == preferredLanguage }) else { return }
        _ = try? await download(match)
    }

    func download(_ track: SubtitleTrack) async throws -> URL {
        let dir = Self.directory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        pruneIfNeeded(dir)

        let file = dir.appendingPathComponent("\(track.languageCode)-\(Self.digest(track.id)).\(Self.fileExtension(for: track.url))")
        if FileManager.default.fileExists(atPath: file.path) { return file }

        var request = URLRequest(url: track.url)
        request.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: request)
        try data.write(to: file, options: .atomic)
        return file
    }

    private static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }

    private static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Subtitles", isDirectory: true)
    }

    private static func fileExtension(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ["srt", "vtt", "ass", "ssa", "sub"].contains(ext) ? ext : "srt"
    }

    private var pruned = false
    private func pruneIfNeeded(_ dir: URL) {
        guard !pruned else { return }
        pruned = true
        let cutoff = Date().addingTimeInterval(-30 * 24 * 3600)
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }

    private func rank(_ code: String) -> Int {
        SubtitleLanguage.common.firstIndex { $0.code == code } ?? Int.max
    }
}
