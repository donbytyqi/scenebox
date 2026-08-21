//
//  AuthStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 01.08.26.
//

import Foundation
import Observation
import FirebaseAuth

@MainActor
@Observable
final class AuthStore {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn(uid: String, email: String?)
    }

    private(set) var state: State = .loading
    private(set) var errorMessage: String?
    private(set) var isWorking = false

    @ObservationIgnored private var handle: AuthStateDidChangeListenerHandle?

    init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            let next: State = user.map { .signedIn(uid: $0.uid, email: $0.email) } ?? .signedOut
            Task { @MainActor in self?.state = next }
        }
    }

    var email: String? {
        if case let .signedIn(_, email) = state { return email }
        return nil
    }

    func signIn(email: String, password: String) async {
        await perform(creating: false) {
            try await Auth.auth().signIn(withEmail: email, password: password)
        }
    }

    func createAccount(email: String, password: String) async {
        await perform(creating: true) {
            try await Auth.auth().createUser(withEmail: email, password: password)
        }
    }

    func signOut() {
        do { try Auth.auth().signOut() } catch { errorMessage = error.localizedDescription }
    }

    func clearError() { errorMessage = nil }

    private func perform(creating: Bool, _ operation: () async throws -> AuthDataResult) async {
        isWorking = true
        errorMessage = nil
        do {
            _ = try await operation()
        } catch {
            errorMessage = Self.message(for: error, creating: creating)
        }
        isWorking = false
    }

    private static func message(for error: Error, creating: Bool) -> String {
        switch (error as NSError).code {
        case 17008:  // invalidEmail
            return "That email address doesn't look right."
        case 17026:  // weakPassword
            return "Choose a stronger password — at least 6 characters."
        case 17020:  // networkError
            return "Network error. Check your connection and try again."
        case 17010:  // tooManyRequests
            return "Too many attempts. Please wait a moment and try again."
        default:
            return creating
                ? "Couldn't create your account. Please check your details and try again."
                : "Incorrect email or password."
        }
    }
}
