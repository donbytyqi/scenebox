//
//  TorrentSearch.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

import Foundation

public enum TorrentioError: LocalizedError {
    case badStatus(Int)
    case emptyResponse
    case notJSON
    case debridRejected
    case badURL

    public var errorDescription: String? {
        switch self {
        case .badStatus(let code):
            "The source service responded with an error (HTTP \(code)). Try again in a moment."
        case .emptyResponse, .notJSON:
            "The source service returned an unexpected response. It may be busy or rate-limiting. Try again shortly."
        case .debridRejected:
            "Your debrid service rejected the API key. Double-check it in Settings › Debrid."
        case .badURL:
            "Couldn’t build a valid request URL."
        }
    }
}

public actor TorrentSearch {
    let cinemetaBase = "https://v3-cinemeta.strem.io"
    let kitsuBase = "https://anime-kitsu.strem.fun"
    private let sourceBases: [String]

    public init(sourceBases: [String] = []) {
        self.sourceBases = sourceBases.isEmpty ? ["https://torrentio.strem.fun"] : sourceBases
    }

    // MARK: - Title search (Cinemeta)

    public func search(_ query: String, type: MediaType = .movie, skip: Int = 0) async throws -> [MediaResult] {
        let q = query.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(.init(charactersIn: "-._~"))) ?? ""
        let extras = skip > 0 ? "search=\(q)&skip=\(skip)" : "search=\(q)"
        let urlString = type == .anime
            ? "\(kitsuBase)/catalog/anime/kitsu-anime-list/\(extras).json"
            : "\(cinemetaBase)/catalog/\(type.rawValue)/top/\(extras).json"
        guard let url = URL(string: urlString) else { throw TorrentioError.badURL }
        let json = try await fetchJSONObject(from: url, attempts: 2, timeout: 6)
        let metas = json["metas"] as? [[String: Any]] ?? []
        return metas.compactMap { Self.parseResult($0, type: type == .anime ? .series : type) }
    }

    public func searchAll(_ query: String) async -> [MediaResult] {
        async let movies = try? search(query, type: .movie)
        async let series = try? search(query, type: .series)
        return (await movies ?? []) + (await series ?? [])
    }

    // MARK: - Streams (Torrentio)

    public func streams(for media: MediaResult, season: Int? = nil, episode: Int? = nil) async throws -> [TorrentStream] {
        try await streams(id: media.id, type: media.type, season: season, episode: episode)
    }

    public func streams(id: String, type: MediaType,
                        season: Int? = nil, episode: Int? = nil) async throws -> [TorrentStream] {
        var id = id
        if type == .series, let e = episode {
            if id.hasPrefix("kitsu:") {
                id += ":\(e)"
            } else if let s = season {
                id += ":\(s):\(e)"
            }
        }
        let path = "stream/\(type.rawValue)/\(id).json"

        let bases = fallbackBases
        var results = [Int: [TorrentStream]](minimumCapacity: bases.count)
        var rejection: Error?
        var lastError: Error?

        try await withThrowingTaskGroup(of: (Int, Result<[TorrentStream], Error>).self) { group in
            for (index, base) in bases.enumerated() {
                guard let url = URL(string: "\(base)/\(path)") else { continue }
                group.addTask {
                    do {
                        let json = try await self.fetchJSONObject(from: url, attempts: 1, timeout: 5)
                        let streams = json["streams"] as? [[String: Any]] ?? []
                        if Self.isDebridRejection(streams) {
                            return (index, .failure(TorrentioError.debridRejected))
                        }
                        return (index, .success(streams.compactMap { self.parseStream($0) }))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            for try await (index, result) in group {
                switch result {
                case .success(let parsed):
                    results[index] = parsed
                    if index == 0, !parsed.isEmpty {
                        group.cancelAll()
                        return
                    }
                case .failure(let error):
                    if error is CancellationError { throw CancellationError() }
                    if let urlError = error as? URLError, urlError.code == .cancelled { throw urlError }
                    if case TorrentioError.debridRejected = error { rejection = error }
                    lastError = error
                }
            }
        }

        for index in bases.indices {
            if let parsed = results[index], !parsed.isEmpty { return parsed }
        }
        if let rejection { throw rejection }
        if let lastError { throw lastError }
        return []
    }

    private var fallbackBases: [String] {
        var seen = Set<String>()
        return sourceBases.filter { seen.insert($0).inserted }
    }

    nonisolated static let userAgent: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        #if os(tvOS)
        let platform = "tvOS"
        #else
        let platform = "iOS"
        #endif
        return "WatchBox/\(version) (\(platform))"
    }()
    nonisolated static let browserUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"

    nonisolated private func fetchJSONObject(from url: URL, attempts: Int = 3,
                                             timeout: TimeInterval = 20) async throws -> [String: Any] {
        var lastError: Error = TorrentioError.emptyResponse

        for attempt in 0..<attempts {
            if attempt > 0 {
                try await Task.sleep(for: .milliseconds(500 * attempt))
            }

            var request = URLRequest(url: url)
            request.timeoutInterval = timeout
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

            do {
                var (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 403 {
                    request.setValue(Self.browserUserAgent, forHTTPHeaderField: "User-Agent")
                    (data, response) = try await URLSession.shared.data(for: request)
                }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    guard (500...599).contains(http.statusCode) || http.statusCode == 429 else {
                        throw TorrentioError.badStatus(http.statusCode)
                    }
                    lastError = TorrentioError.badStatus(http.statusCode)
                    continue
                }
                guard !data.isEmpty else { lastError = TorrentioError.emptyResponse; continue }
                guard let object = try? JSONSerialization.jsonObject(with: data),
                      let json = object as? [String: Any] else {
                    lastError = TorrentioError.notJSON
                    continue
                }
                return json
            } catch let urlError as URLError {
                if urlError.code == .cancelled { throw urlError }
                lastError = urlError
            }
        }
        throw lastError
    }

    private static func isDebridRejection(_ streams: [[String: Any]]) -> Bool {
        let hasRealResult = streams.contains { s in
            (s["infoHash"] as? String) != nil
                || ((s["url"] as? String).map { !$0.contains("failed_access") } ?? false)
        }
        guard !hasRealResult else { return false }
        return streams.contains { s in
            let url = (s["url"] as? String) ?? ""
            let text = (((s["title"] as? String) ?? "") + " " + ((s["name"] as? String) ?? "")).lowercased()
            return url.contains("failed_access")
                || (text.contains("invalid") && (text.contains("apikey") || text.contains("token") || text.contains("api key")))
        }
    }

    nonisolated private func parseStream(_ dict: [String: Any]) -> TorrentStream? {
        let hashHex = dict["infoHash"] as? String
        let infoHash = hashHex.flatMap { Data(hex: $0) }
        let url = (dict["url"] as? String).flatMap(URL.init(string:))
        guard infoHash != nil || url != nil else { return nil }

        let name = (dict["name"] as? String) ?? "Torrentio"
        let title = (dict["title"] as? String) ?? name
        let fileIdx = dict["fileIdx"] as? Int

        var trackers: [URL] = []
        if let sources = dict["sources"] as? [String] {
            for s in sources where s.hasPrefix("tracker:") {
                if let u = URL(string: String(s.dropFirst("tracker:".count))) { trackers.append(u) }
            }
        }

        return TorrentStream(
            id: hashHex?.lowercased() ?? url?.absoluteString ?? title,
            title: title,
            displayName: cleanName(name),
            infoHash: infoHash ?? Data(),
            fileIndex: fileIdx,
            trackers: trackers,
            seeders: extractSeeders(title),
            sizeText: extractSize(title),
            resolution: extractResolution(name),
            url: url
        )
    }

    // MARK: - Title parsing helpers

    nonisolated private func cleanName(_ s: String) -> String {
        s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }

    nonisolated private func extractSeeders(_ title: String) -> Int? {
        guard let range = title.range(of: "👤") else { return nil }
        let after = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        let digits = after.prefix { $0.isNumber }
        return Int(digits)
    }

    nonisolated private func extractSize(_ title: String) -> String? {
        guard let range = title.range(of: "💾") else { return nil }
        let after = title[range.upperBound...].trimmingCharacters(in: .whitespaces)
        return after.split(separator: " ").prefix(2).joined(separator: " ")
    }

    nonisolated private func extractResolution(_ name: String) -> String? {
        let lowered = name.lowercased()
        if lowered.contains("4k") || lowered.contains("2160p") { return "2160p" }
        for res in ["1080p", "720p", "480p"] where lowered.contains(res) { return res }
        return nil
    }
}
