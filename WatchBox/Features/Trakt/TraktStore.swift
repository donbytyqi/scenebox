//
//  TraktStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation
import Observation
#if os(iOS)
import AuthenticationServices
#endif

@MainActor
@Observable
final class TraktStore {
    static let shared = TraktStore()

    private(set) var pendingCode: TraktDeviceCode?
    private(set) var isAuthorizing = false
    private(set) var authError: String?
    var pendingBackfillOffer = false

    private(set) var lists: [TraktListSummary] = []
    private(set) var isLoadingLists = false
    private(set) var listsError: String?
    private(set) var itemsByList: [String: [MediaResult]] = [:]
    private(set) var loadingListID: String?
    private(set) var itemsError: String?

    @ObservationIgnored private var authTask: Task<Void, Never>?
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    var isConnected: Bool { settings.traktConnected }

    var isConfigured: Bool { TraktConfig.isConfigured }

    private var client: TraktClient? { TraktClient() }

    #if os(iOS)
    // MARK: - Web authorization

    func signIn() {
        guard authTask == nil, let client else { return }
        authError = nil
        isAuthorizing = true

        authTask = Task {
            defer {
                isAuthorizing = false
                authTask = nil
            }
            do {
                let state = UUID().uuidString
                guard let url = client.authorizeURL(state: state) else { throw TraktError.badURL }
                let callback = try await TraktWebAuth.shared.authorize(url: url)
                let code = try Self.authorizationCode(from: callback, expectedState: state)
                let tokens = try await client.exchangeCode(code)
                settings.traktAccessToken = tokens.accessToken
                settings.traktRefreshToken = tokens.refreshToken
                settings.traktTokenExpiry = tokens.expiresAt
                settings.traktUsername = await client.username(accessToken: tokens.accessToken) ?? ""
                pendingBackfillOffer = settings.traktUsername != settings.traktBackfillUsername
            } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                authError = error.localizedDescription
            }
        }
    }

    nonisolated private static func authorizationCode(from url: URL, expectedState: String) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard items.first(where: { $0.name == "state" })?.value == expectedState,
              let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            throw TraktError.badResponse
        }
        return code
    }
    #endif

    // MARK: - Device authorization

    func beginDeviceAuth() {
        guard authTask == nil, let client else { return }
        authError = nil
        isAuthorizing = true

        authTask = Task {
            defer {
                isAuthorizing = false
                pendingCode = nil
                authTask = nil
            }
            do {
                let code = try await client.requestDeviceCode()
                guard !Task.isCancelled else { return }
                pendingCode = code

                let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))
                var interval = max(code.interval, 1)
                while Date() < deadline, !Task.isCancelled {
                    try await Task.sleep(for: .seconds(interval))
                    guard !Task.isCancelled else { return }
                    if let tokens = try await client.pollDeviceToken(deviceCode: code.deviceCode) {
                        settings.traktAccessToken = tokens.accessToken
                        settings.traktRefreshToken = tokens.refreshToken
                        settings.traktTokenExpiry = tokens.expiresAt
                        settings.traktUsername = await client.username(accessToken: tokens.accessToken) ?? ""
                        pendingBackfillOffer = settings.traktUsername != settings.traktBackfillUsername
                        return
                    }
                    interval = min(interval + 1, 10)
                }
                if !Task.isCancelled { authError = TraktError.codeExpired.errorDescription }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                authError = error.localizedDescription
            }
        }
    }

    func cancelDeviceAuth() {
        authTask?.cancel()
        authTask = nil
        pendingCode = nil
        isAuthorizing = false
    }

    func disconnect() {
        cancelDeviceAuth()
        let token = settings.traktAccessToken
        if let client, !token.isEmpty {
            Task { await client.revoke(accessToken: token) }
        }
        settings.clearTraktSession()
        lists = []
        itemsByList = [:]
        listsError = nil
        itemsError = nil
    }

    // MARK: - Token upkeep

    func validAccessToken() async -> String? {
        guard isConnected else { return nil }
        let now = Date().timeIntervalSince1970
        guard settings.traktTokenExpiry > 0, now > settings.traktTokenExpiry - 86_400 else {
            return settings.traktAccessToken
        }
        guard let client else { return settings.traktAccessToken }
        do {
            let tokens = try await client.refreshTokens(refreshToken: settings.traktRefreshToken)
            settings.traktAccessToken = tokens.accessToken
            settings.traktRefreshToken = tokens.refreshToken
            settings.traktTokenExpiry = tokens.expiresAt
            return tokens.accessToken
        } catch {
            if now < settings.traktTokenExpiry { return settings.traktAccessToken }
            settings.clearTraktSession()
            return nil
        }
    }

    // MARK: - Lists

    func loadLists(force: Bool = false) async {
        guard isConnected, !isLoadingLists else { return }
        if !force, !lists.isEmpty { return }
        isLoadingLists = true
        listsError = nil
        defer { isLoadingLists = false }

        guard let client, let token = await validAccessToken() else {
            listsError = TraktError.unauthorized.errorDescription
            return
        }
        var all: [TraktListSummary] = [
            TraktListSummary(kind: .watchlist, name: "Watchlist", itemCount: nil),
            TraktListSummary(kind: .favorites, name: "Favorites", itemCount: nil),
        ]
        do {
            all += try await client.personalLists(accessToken: token)
            lists = all
        } catch {
            lists = all
            listsError = error.localizedDescription
        }
    }

    func items(for list: TraktListSummary, force: Bool = false) async -> [MediaResult]? {
        if !force, let cached = itemsByList[list.id] { return cached }
        guard loadingListID == nil else { return itemsByList[list.id] }
        loadingListID = list.id
        itemsError = nil
        defer { loadingListID = nil }

        guard let client, let token = await validAccessToken() else {
            itemsError = TraktError.unauthorized.errorDescription
            return nil
        }
        do {
            let fetched: [MediaResult]
            switch list.kind {
            case .watchlist: fetched = try await client.watchlist(accessToken: token)
            case .favorites: fetched = try await client.favorites(accessToken: token)
            case .personal(let id): fetched = try await client.listItems(listID: id, accessToken: token)
            }
            itemsByList[list.id] = fetched
            return fetched
        } catch {
            itemsError = error.localizedDescription
            return nil
        }
    }

    // MARK: - Import

    func importToWatchlist(_ items: [MediaResult], watchlist: WatchlistStore) -> Int {
        var added = 0
        for item in items where !watchlist.contains(item.id) {
            watchlist.toggle(id: item.id, mediaType: item.type,
                             title: item.name, posterURL: item.posterURL)
            added += 1
        }
        return added
    }
}
