//
//  TraktWebAuth.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

#if os(iOS)
import AuthenticationServices
import UIKit

@MainActor
final class TraktWebAuth: NSObject, @preconcurrency ASWebAuthenticationPresentationContextProviding {
    static let shared = TraktWebAuth()

    private var session: ASWebAuthenticationSession?

    func authorize(url: URL) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: TraktConfig.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? TraktError.badResponse)
                }
            }
            session.presentationContextProvider = self
            self.session = session
            session.start()
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
#endif
