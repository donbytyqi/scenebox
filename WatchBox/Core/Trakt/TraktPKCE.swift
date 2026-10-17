//
//  TraktPKCE.swift
//  SceneBox
//
//  Created by SpontaneousArray on 11.10.26.
//

import CryptoKit
import Foundation

/// PKCE (Proof Key for Code Exchange) helpers for the Trakt authorization flow.
///
/// PKCE lets a public client — an app that cannot keep a secret — prove that it
/// is the same app that started a sign-in. The app sends a SHA-256 *challenge*
/// with the authorize request and the original *verifier* when exchanging the
/// code, so an intercepted authorization code is useless on its own. This is
/// what replaced the app's client-secret backend.
nonisolated enum TraktPKCE {
    /// A fresh verifier for one sign-in. Trakt requires 43–128 characters from
    /// the unreserved set `A-Z a-z 0-9 - . _ ~`; 64 characters of that alphabet
    /// is ~384 bits of entropy.
    static func makeVerifier() -> String {
        let allowed = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<64).map { _ in allowed[Int.random(in: 0..<allowed.count)] })
    }

    /// `BASE64URL(SHA256(verifier))` without padding — Trakt only supports S256.
    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
