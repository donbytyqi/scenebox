//
//  TraktClient.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation

// MARK: - Models

nonisolated public struct TraktDeviceCode: Sendable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: String
    public let interval: Int
    public let expiresIn: Int
}

nonisolated public struct TraktTokens: Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Double   // unix timestamp
}

nonisolated public struct TraktListSummary: Identifiable, Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case watchlist
        case favorites
        case personal(Int)         // Trakt list id
    }

    public let kind: Kind
    public let name: String
    public let itemCount: Int?

    public var id: String {
        switch kind {
        case .watchlist: "watchlist"
        case .favorites: "favorites"
        case .personal(let id): "list-\(id)"
        }
    }
}

nonisolated public struct TraktHistoryItem: Sendable {
    public let imdbID: String
    public let season: Int?
    public let episode: Int?
    public let watchedAt: Date?

    public init(imdbID: String, season: Int? = nil, episode: Int? = nil, watchedAt: Date? = nil) {
        self.imdbID = imdbID
        self.season = season
        self.episode = episode
        self.watchedAt = watchedAt
    }
}

nonisolated public enum TraktError: Error, LocalizedError {
    case badURL
    case badResponse
    case authorizationDenied
    case codeExpired
    case unauthorized
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .badURL: "Couldn’t build a valid Trakt URL."
        case .badResponse: "Trakt returned an unexpected response."
        case .authorizationDenied: "The Trakt authorization was denied."
        case .codeExpired: "The code expired before it was approved. Try again."
        case .unauthorized: "Trakt session expired. Reconnect your account."
        case .http(let code): "Trakt request failed (HTTP \(code))."
        }
    }
}

// MARK: - Client

public actor TraktClient {
    private let clientID: String
    private let base = "https://api.trakt.tv"

    public init?() {
        guard TraktConfig.isConfigured else { return nil }
        clientID = TraktConfig.clientID
    }

    // MARK: Web auth

    nonisolated public func authorizeURL(state: String) -> URL? {
        var comps = URLComponents(string: "https://trakt.tv/oauth/authorize")
        comps?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: TraktConfig.redirectURI),
            URLQueryItem(name: "state", value: state),
        ]
        return comps?.url
    }

    public func exchangeCode(_ code: String) async throws -> TraktTokens {
        try parseTokens(try await postAuth("/exchange", body: ["code": code]))
    }

    // MARK: Device auth

    public func requestDeviceCode() async throws -> TraktDeviceCode {
        let obj = try await post("/oauth/device/code", body: ["client_id": clientID])
        guard let device = obj["device_code"] as? String,
              let user = obj["user_code"] as? String,
              let url = obj["verification_url"] as? String else { throw TraktError.badResponse }
        return TraktDeviceCode(
            deviceCode: device,
            userCode: user,
            verificationURL: url,
            interval: obj["interval"] as? Int ?? 5,
            expiresIn: obj["expires_in"] as? Int ?? 600)
    }

    public func pollDeviceToken(deviceCode: String) async throws -> TraktTokens? {
        do {
            return try parseTokens(try await postAuth("/device/token", body: ["code": deviceCode]))
        } catch TraktError.http(let status) {
            switch status {
            case 400, 404, 409, 429: return nil   // pending, invalid, or slow down
            case 410: throw TraktError.codeExpired
            case 418: throw TraktError.authorizationDenied
            default: throw TraktError.http(status)
            }
        }
    }

    public func refreshTokens(refreshToken: String) async throws -> TraktTokens {
        try parseTokens(try await postAuth("/refresh", body: ["refresh_token": refreshToken]))
    }

    public func revoke(accessToken: String) async {
        _ = try? await postAuth("/revoke", body: ["token": accessToken])
    }

    private func parseTokens(_ obj: [String: Any]) throws -> TraktTokens {
        guard let access = obj["access_token"] as? String,
              let refresh = obj["refresh_token"] as? String else { throw TraktError.badResponse }
        let created = obj["created_at"] as? Double ?? Date().timeIntervalSince1970
        let lifetime = obj["expires_in"] as? Double ?? 7776000
        return TraktTokens(accessToken: access, refreshToken: refresh,
                           expiresAt: created + lifetime)
    }

    // MARK: User data

    public func username(accessToken: String) async -> String? {
        guard let obj = try? await getObject("/users/settings", accessToken: accessToken),
              let user = obj["user"] as? [String: Any] else { return nil }
        return user["username"] as? String
    }

    public func watchlist(accessToken: String) async throws -> [MediaResult] {
        try await items(at: "/sync/watchlist/movies", accessToken: accessToken)
            + items(at: "/sync/watchlist/shows", accessToken: accessToken)
    }

    public func favorites(accessToken: String) async throws -> [MediaResult] {
        try await items(at: "/sync/favorites/movies", accessToken: accessToken)
            + items(at: "/sync/favorites/shows", accessToken: accessToken)
    }

    public func personalLists(accessToken: String) async throws -> [TraktListSummary] {
        let lists = try await getArray("/users/me/lists", accessToken: accessToken)
        return lists.compactMap { list in
            guard let name = list["name"] as? String,
                  let ids = list["ids"] as? [String: Any],
                  let id = ids["trakt"] as? Int else { return nil }
            return TraktListSummary(kind: .personal(id), name: name,
                                    itemCount: list["item_count"] as? Int)
        }
    }

    public func listItems(listID: Int, accessToken: String) async throws -> [MediaResult] {
        try await items(at: "/users/me/lists/\(listID)/items/movies,shows",
                        accessToken: accessToken)
    }

    private func items(at path: String, accessToken: String) async throws -> [MediaResult] {
        try await getArray(path, accessToken: accessToken).compactMap(Self.parseItem)
    }

    // MARK: Sync (app → Trakt)

    public func addToHistory(_ items: [TraktHistoryItem], accessToken: String) async throws {
        guard !items.isEmpty else { return }
        _ = try await post("/sync/history",
                           body: Self.historyPayload(items, includeDates: true),
                           accessToken: accessToken)
    }

    public func removeFromHistory(_ items: [TraktHistoryItem], accessToken: String) async throws {
        guard !items.isEmpty else { return }
        _ = try await post("/sync/history/remove",
                           body: Self.historyPayload(items, includeDates: false),
                           accessToken: accessToken)
    }

    public func addToWatchlist(movieIDs: [String], showIDs: [String], accessToken: String) async throws {
        guard !movieIDs.isEmpty || !showIDs.isEmpty else { return }
        _ = try await post("/sync/watchlist",
                           body: Self.idsPayload(movieIDs: movieIDs, showIDs: showIDs),
                           accessToken: accessToken)
    }

    public func removeFromWatchlist(movieIDs: [String], showIDs: [String], accessToken: String) async throws {
        guard !movieIDs.isEmpty || !showIDs.isEmpty else { return }
        _ = try await post("/sync/watchlist/remove",
                           body: Self.idsPayload(movieIDs: movieIDs, showIDs: showIDs),
                           accessToken: accessToken)
    }

    nonisolated private static func historyPayload(_ items: [TraktHistoryItem],
                                                   includeDates: Bool) -> [String: Any] {
        var movies: [[String: Any]] = []
        var episodes: [String: [Int: [[String: Any]]]] = [:]   // show imdb → season → entries

        for item in items {
            if let season = item.season, let episode = item.episode {
                var entry: [String: Any] = ["number": episode]
                if includeDates, let at = item.watchedAt {
                    entry["watched_at"] = iso(at)
                }
                episodes[item.imdbID, default: [:]][season, default: []].append(entry)
            } else {
                var entry: [String: Any] = ["ids": ["imdb": item.imdbID]]
                if includeDates, let at = item.watchedAt {
                    entry["watched_at"] = iso(at)
                }
                movies.append(entry)
            }
        }

        let shows: [[String: Any]] = episodes.map { imdb, seasons in
            ["ids": ["imdb": imdb],
             "seasons": seasons.map { number, entries in
                 ["number": number, "episodes": entries]
             }]
        }
        return ["movies": movies, "shows": shows]
    }

    nonisolated private static func idsPayload(movieIDs: [String], showIDs: [String]) -> [String: Any] {
        [
            "movies": movieIDs.map { ["ids": ["imdb": $0]] },
            "shows": showIDs.map { ["ids": ["imdb": $0]] },
        ]
    }

    nonisolated private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    nonisolated private static func parseItem(_ entry: [String: Any]) -> MediaResult? {
        guard let kind = entry["type"] as? String,
              kind == "movie" || kind == "show",
              let media = entry[kind] as? [String: Any],
              let title = media["title"] as? String,
              let ids = media["ids"] as? [String: Any],
              let imdb = ids["imdb"] as? String, imdb.hasPrefix("tt") else { return nil }
        return MediaResult(
            id: imdb,
            type: kind == "movie" ? .movie : .series,
            name: title,
            year: (media["year"] as? Int).map(String.init),
            posterURL: URL(string: "https://images.metahub.space/poster/medium/\(imdb)/img"),
            description: nil)
    }

    // MARK: Plumbing

    private func headers(_ accessToken: String? = nil) -> [String: String] {
        var headers = ["trakt-api-version": "2", "trakt-api-key": clientID]
        if let accessToken { headers["Authorization"] = "Bearer \(accessToken)" }
        return headers
    }

    private func apiURL(_ path: String) throws -> URL {
        guard let url = URL(string: "\(base)\(path)") else { throw TraktError.badURL }
        return url
    }

    private func post(_ path: String, body: [String: Any],
                      accessToken: String? = nil) async throws -> [String: Any] {
        let response = try await HTTP.post(apiURL(path), json: body, headers: headers(accessToken))
        try Self.check(response)
        return response.object ?? [:]
    }

    private func postAuth(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "\(TraktConfig.authEndpoint)\(path)") else {
            throw TraktError.badURL
        }
        let response = try await HTTP.post(url, json: body)
        try Self.check(response)
        return response.object ?? [:]
    }

    private func getObject(_ path: String, accessToken: String) async throws -> [String: Any] {
        let response = try await HTTP.get(apiURL(path), headers: headers(accessToken))
        try Self.check(response)
        guard let object = response.object else { throw TraktError.badResponse }
        return object
    }

    private func getArray(_ path: String, accessToken: String) async throws -> [[String: Any]] {
        let response = try await HTTP.get(apiURL(path), headers: headers(accessToken))
        try Self.check(response)
        guard let array = response.array else { throw TraktError.badResponse }
        return array
    }

    nonisolated private static func check(_ response: HTTP.Response) throws {
        switch response.status {
        case 200..<300: return
        case 401, 403: throw TraktError.unauthorized
        default: throw TraktError.http(response.status)
        }
    }
}
