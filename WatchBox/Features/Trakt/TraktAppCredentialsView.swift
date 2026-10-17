//
//  TraktAppCredentialsView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 11.10.26.
//

import SwiftUI

/// Lets the user point SceneBox at their own Trakt application instead of the
/// one bundled with the app.
///
/// Sign-in uses PKCE, so a client secret is not required and the app's own
/// Trakt application does not use one. The field exists only for an older
/// application that still expects a secret.
struct TraktAppCredentialsView: View {
    @AppStorage(TraktConfig.clientIDKey) private var clientID = ""
    @AppStorage(TraktConfig.clientSecretKey) private var clientSecret = ""

    private var usingCustomApp: Bool {
        !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section {
                TextField("Client ID", text: $clientID)
                    .autocorrectionDisabled()
                    .tint(.white)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                SecureField("Client secret (optional)", text: $clientSecret)
                    .autocorrectionDisabled()
                    .tint(.white)
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif
            } header: {
                Text("Your Trakt application")
            } footer: {
                Text("Leave both empty to use the Trakt application bundled with SceneBox. Create your own at trakt.tv/oauth/applications and add \(TraktConfig.redirectURI) as a redirect URI.\n\nA client secret is not needed: sign-in uses PKCE.")
            }

            if usingCustomApp {
                Section {
                    Button("Use the bundled Trakt application", role: .destructive) {
                        clientID = ""
                        clientSecret = ""
                    }
                } footer: {
                    Text("Sign in with Trakt again after switching applications.")
                }
            }
        }
        .hideScrollBackground()
        .background(Theme.background)
        .navigationTitle("Trakt app")
        .tint(.white)
    }
}
