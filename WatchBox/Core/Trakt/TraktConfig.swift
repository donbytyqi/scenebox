//
//  TraktConfig.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation

// Client ID from trakt.tv/oauth/applications (the app must list
// scenebox://trakt-auth as an allowed redirect URI). The client secret
// stays in the scenebox-backend Firebase function behind authEndpoint.
nonisolated enum TraktConfig {
    static let clientID = "Wza1WExhiestCkCc_Gc9QE6i9Eyv448wRsopgrVDP8Q"
    static let authEndpoint = "https://us-central1-watchbox-8869b.cloudfunctions.net/trakt"
    static let redirectURI = "scenebox://trakt-auth"
    static let callbackScheme = "scenebox"

    static var isConfigured: Bool { !clientID.isEmpty }
}
