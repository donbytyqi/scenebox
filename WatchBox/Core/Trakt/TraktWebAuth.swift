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
            let oneShot = ContinuationGuard(continuation)

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: TraktConfig.callbackScheme,
                completionHandler: Self.completionHandler(for: oneShot)
            )
            session.presentationContextProvider = self
            self.session = session

            // On Mac Catalyst this dry-runs the session against SafariLaunchAgent.
            // A false return means it never started, so fail instead of hanging.
            if !session.start() {
                oneShot.resume(throwing: TraktError.badResponse)
            }
        }
    }

    /// `ASWebAuthenticationSession` invokes its completion handler on its own
    /// XPC queue (`com.apple.NSXPCConnection.m-user.com.apple.SafariLaunchAgent`),
    /// never on the main actor. Because this module builds with
    /// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, a closure written inline in
    /// `authorize(url:)` would be inferred `@MainActor`, and the runtime's
    /// dynamic isolation check would trap (`_swift_task_checkIsolatedSwift` →
    /// `_dispatch_assert_queue_fail`) the moment the auth window opened.
    /// Returning the closure from a `nonisolated` function keeps it free of
    /// actor isolation so it can run on whatever queue the framework uses.
    private nonisolated static func completionHandler(
        for oneShot: ContinuationGuard
    ) -> @Sendable (URL?, Error?) -> Void {
        { url, error in
            if let url {
                oneShot.resume(returning: url)
            } else {
                oneShot.resume(throwing: error ?? TraktError.badResponse)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        return windows.first { $0.isKeyWindow }
            ?? windows.first
            ?? scenes.first.map { ASPresentationAnchor(windowScene: $0) }
            ?? ASPresentationAnchor()
    }
}

/// One-shot continuation guard. `session.start()` returning false and the
/// completion handler firing are not mutually exclusive, and resuming a
/// `CheckedContinuation` twice traps.
///
/// `nonisolated` because the project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which would otherwise make
/// these members main-actor isolated and uncallable from the framework's queue.
/// The lock, not an actor, provides the synchronisation.
private nonisolated final class ContinuationGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var finished = false
    private let continuation: CheckedContinuation<URL, Error>

    init(_ continuation: CheckedContinuation<URL, Error>) {
        self.continuation = continuation
    }

    func resume(returning url: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(returning: url)
    }

    func resume(throwing error: Error) {
        lock.lock()
        defer { lock.unlock() }
        guard !finished else { return }
        finished = true
        continuation.resume(throwing: error)
    }
}
#endif
