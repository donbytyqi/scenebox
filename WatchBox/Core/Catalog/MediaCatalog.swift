//
//  MediaCatalog.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation

// MARK: - Cinemeta browse + detail

extension TorrentSearch {
    public func catalog(
        type: MediaType,
        feed: CatalogFeed = .popular,
        genre: String? = nil,
        skip: Int = 0
    ) async throws -> [MediaResult] {
        let isAnime = type == .anime
        let base = isAnime ? kitsuBase : cinemetaBase
        var path = "catalog/\(isAnime ? "anime" : type.rawValue)/\(isAnime ? feed.kitsuCatalog : feed.rawValue)"
        var extras: [String] = []
        if let genre, !genre.isEmpty {
            let encoded = genre.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? genre
            extras.append("genre=\(encoded)")
        }
        if skip > 0 { extras.append("skip=\(skip)") }
        if !extras.isEmpty { path += "/" + extras.joined(separator: "&") }

        guard let url = URL(string: "\(base)/\(path).json") else { throw CatalogError.badURL }
        let (data, _) = try await URLSession.shared.data(for: Self.request(url))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let metas = json?["metas"] as? [[String: Any]] ?? []
        return metas.compactMap { Self.parseResult($0, type: isAnime ? .series : type) }
    }

    public func detail(id: String, type: MediaType) async throws -> MediaDetail {
        let isKitsu = id.hasPrefix("kitsu:")
        let base = isKitsu ? kitsuBase : cinemetaBase
        let typePath = isKitsu ? "anime" : type.rawValue
        let safeID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        guard let url = URL(string: "\(base)/meta/\(typePath)/\(safeID).json") else {
            throw CatalogError.badURL
        }
        let (data, _) = try await URLSession.shared.data(for: Self.request(url))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let meta = json?["meta"] as? [String: Any] else {
            throw CatalogError.notFound(id)
        }
        return Self.parseDetail(meta, fallbackType: type)
    }

    nonisolated private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(TorrentSearch.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    // MARK: Parsing

    static func parseResult(_ meta: [String: Any], type: MediaType) -> MediaResult? {
        guard let id = meta["id"] as? String, let name = meta["name"] as? String else { return nil }
        return MediaResult(
            id: id,
            type: (meta["type"] as? String).flatMap(MediaType.init(rawValue:)) ?? type,
            name: name,
            year: (meta["releaseInfo"] as? String) ?? stringValue(meta["year"]),
            posterURL: (meta["poster"] as? String).flatMap(URL.init(string:)),
            description: meta["description"] as? String
        )
    }

    static func parseDetail(_ meta: [String: Any], fallbackType: MediaType) -> MediaDetail {
        let type = (meta["type"] as? String).flatMap(MediaType.init(rawValue:)) ?? fallbackType
        let videos = meta["videos"] as? [[String: Any]] ?? []

        return MediaDetail(
            id: (meta["id"] as? String) ?? (meta["imdb_id"] as? String) ?? "",
            type: type,
            name: (meta["name"] as? String) ?? "Untitled",
            year: (meta["releaseInfo"] as? String) ?? stringValue(meta["year"]),
            posterURL: (meta["poster"] as? String).flatMap(URL.init(string:)),
            backdropURL: (meta["background"] as? String).flatMap(URL.init(string:)),
            logoURL: (meta["logo"] as? String).flatMap(URL.init(string:)),
            description: meta["description"] as? String,
            cast: stringList(meta["cast"]),
            directors: stringList(meta["director"]),
            writers: stringList(meta["writer"]),
            genres: stringList(meta["genres"] ?? meta["genre"]),
            imdbRating: doubleValue(meta["imdbRating"]),
            runtime: meta["runtime"] as? String,
            released: (meta["released"] as? String).flatMap(parseDate),
            country: meta["country"] as? String,
            awards: meta["awards"] as? String,
            episodes: videos.compactMap(parseEpisode),
            moviedbID: intValue(meta["moviedb_id"]),
            trailerYouTubeIDs: parseTrailers(meta["trailers"])
        )
    }

    private static func parseTrailers(_ any: Any?) -> [String] {
        guard let list = any as? [[String: Any]] else { return [] }
        let items = list.compactMap { entry -> (id: String, isTrailer: Bool)? in
            guard let id = entry["source"] as? String, !id.isEmpty else { return nil }
            return (id, (entry["type"] as? String)?.lowercased() == "trailer")
        }
        return items.filter(\.isTrailer).map(\.id) + items.filter { !$0.isTrailer }.map(\.id)
    }

    private static func intValue(_ any: Any?) -> Int? {
        switch any {
        case let number as Int: number
        case let number as Double: Int(number)
        case let text as String: Int(text)
        default: nil
        }
    }

    private static func parseEpisode(_ video: [String: Any]) -> Episode? {
        guard let id = video["id"] as? String else { return nil }
        let season = video["season"] as? Int ?? 0
        guard let number = video["episode"] as? Int ?? video["number"] as? Int else { return nil }

        return Episode(
            id: id,
            season: season,
            episode: number,
            name: (video["name"] as? String) ?? "Episode \(number)",
            overview: (video["overview"] as? String) ?? (video["description"] as? String),
            thumbnailURL: (video["thumbnail"] as? String).flatMap(URL.init(string:)),
            released: (video["released"] as? String ?? video["firstAired"] as? String).flatMap(parseDate)
        )
    }

    private static func stringValue(_ any: Any?) -> String? {
        switch any {
        case let text as String: text
        case let number as Int: String(number)
        case let number as Double: String(Int(number))
        default: nil
        }
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let number as Double: number
        case let number as Int: Double(number)
        case let text as String: Double(text)
        default: nil
        }
    }

    private static func stringList(_ any: Any?) -> [String] {
        switch any {
        case let list as [String]: list
        case let single as String: [single]
        default: []
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        ISO8601DateFormatter().date(from: text)
            ?? ISO8601DateFormatter.withFractionalSeconds.date(from: text)
    }
}

nonisolated public enum CatalogError: Error, LocalizedError {
    case notFound(String)
    case badURL

    public var errorDescription: String? {
        switch self {
        case .notFound(let id): "No metadata for \(id)."
        case .badURL: "Couldn’t build a valid catalog URL."
        }
    }
}

nonisolated extension ISO8601DateFormatter {
    nonisolated(unsafe) static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
