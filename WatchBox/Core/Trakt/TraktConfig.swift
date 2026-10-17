//
//  TraktConfig.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation

/// Trakt application credentials and endpoints.
///
/// Sign-in uses PKCE, so no client secret is needed: the app generates a
/// one-time `code_verifier`, sends its SHA-256 challenge with the authorize
/// request, and proves possession of the verifier when exchanging the code.
/// That is why there is no `authEndpoint` any more — the previous build routed
/// the exchange through a Firebase function that held a client secret, and that
/// function is dead (it answers 503), which broke sign-in for everyone.
///
/// A user-supplied client ID can replace the bundled one from Settings, which
/// removes the last dependency on the app author's Trakt application.
nonisolated enum TraktConfig {
    /// The app's own Trakt application, used unless the user supplies their own.
    static let defaultClientID = "Wza1WExhiestCkCc_Gc9QE6i9Eyv448wRsopgrVDP8Q"

    /// UserDefaults keys backing the Settings override.
    static let clientIDKey = "traktClientID"
    static let clientSecretKey = "traktClientSecret"

    /// The effective client ID: the user's if set, otherwise the bundled one.
    static var clientID: String {
        if let custom = UserDefaults.standard.string(forKey: clientIDKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            return custom
        }
        return defaultClientID
    }

    /// Only needed for a user-supplied Trakt app that predates PKCE support.
    /// The app's own application does not use a secret at all.
    static var clientSecret: String? {
        guard let value = UserDefaults.standard.string(forKey: clientSecretKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    static var usesCustomApp: Bool { clientID != defaultClientID }

    // The app must list scenebox://trakt-auth as an allowed redirect URI.
    static let redirectURI = "scenebox://trakt-auth"
    static let callbackScheme = "scenebox"

    static let base = "https://api.trakt.tv"
    static let authorizeEndpoint = "https://auth.trakt.tv/oauth/authorize"
    static let tokenEndpoint = "https://api.trakt.tv/oauth/token"

    static var isConfigured: Bool { !clientID.isEmpty }
}
