//
//  CloudSettingsSync.swift
//  SceneBox
//
//  Created by SpontaneousArray on 04.08.26.
//

import Foundation
import FirebaseFirestore
import Observation

@MainActor
final class CloudSettingsSync {
    static let shared = CloudSettingsSync()

    private let settings: AppSettings
    private var listener: ListenerRegistration?
    private var document: DocumentReference?
    private var pushTask: Task<Void, Never>?
    private var lastSyncedPayload: [String: Any]?
    private var observing = false

    private init(settings: AppSettings = .shared) {
        self.settings = settings
    }

    func activate(uid: String) {
        deactivate()
        let document = Firestore.firestore()
            .collection("users").document(uid)
            .collection("settings").document("apiKeys")
        self.document = document

        listener = document.addSnapshotListener { [weak self] snapshot, _ in
            guard let snapshot, !snapshot.metadata.hasPendingWrites else { return }
            let remote = Remote(snapshot.data() ?? [:])
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !remote.isEmpty {
                    self.apply(remote)
                } else {
                    self.schedulePush(debounce: false)
                }
            }
        }
        startObservingLocalChanges()
    }

    func deactivate() {
        listener?.remove()
        listener = nil
        document = nil
        pushTask?.cancel()
        pushTask = nil
        lastSyncedPayload = nil
    }

    // MARK: Remote → local

    private struct Remote: Sendable {
        let debridAPIKeys: [String: String]?
        let debridProvider: String?
        let tmdbAPIKey: String?
        let preferredSubtitleLanguage: String?
        let preferredAudioLanguage: String?

        init(_ data: [String: Any]) {
            debridAPIKeys = data["debridAPIKeys"] as? [String: String]
            debridProvider = data["debridProvider"] as? String
            tmdbAPIKey = data["tmdbAPIKey"] as? String
            preferredSubtitleLanguage = data["preferredSubtitleLanguage"] as? String
            preferredAudioLanguage = data["preferredAudioLanguage"] as? String
        }

        var isEmpty: Bool {
            debridAPIKeys == nil && debridProvider == nil && tmdbAPIKey == nil
                && preferredSubtitleLanguage == nil && preferredAudioLanguage == nil
        }
        var payload: [String: Any] {
            var out: [String: Any] = [:]
            if let debridAPIKeys { out["debridAPIKeys"] = debridAPIKeys }
            if let debridProvider { out["debridProvider"] = debridProvider }
            if let tmdbAPIKey { out["tmdbAPIKey"] = tmdbAPIKey }
            if let preferredSubtitleLanguage { out["preferredSubtitleLanguage"] = preferredSubtitleLanguage }
            if let preferredAudioLanguage { out["preferredAudioLanguage"] = preferredAudioLanguage }
            return out
        }
    }

    private func apply(_ remote: Remote) {
        lastSyncedPayload = Self.normalize(remote.payload)
        if let keys = remote.debridAPIKeys, keys != settings.debridAPIKeys {
            settings.debridAPIKeys = keys
        }
        if let raw = remote.debridProvider,
           let provider = DebridProvider(rawValue: raw), provider != settings.debridProvider {
            settings.debridProvider = provider
        }
        if let tmdb = remote.tmdbAPIKey, tmdb != settings.tmdbAPIKey {
            settings.tmdbAPIKey = tmdb
        }
        if let subs = remote.preferredSubtitleLanguage, subs != settings.preferredSubtitleLanguage {
            settings.preferredSubtitleLanguage = subs
        }
        if let audio = remote.preferredAudioLanguage, audio != settings.preferredAudioLanguage {
            settings.preferredAudioLanguage = audio
        }
    }

    // MARK: Local → remote

    private func startObservingLocalChanges() {
        guard !observing else { return }
        observing = true
        observeOnce()
    }

    private func observeOnce() {
        withObservationTracking {
            _ = settings.debridAPIKeys
            _ = settings.debridProvider
            _ = settings.tmdbAPIKey
            _ = settings.preferredSubtitleLanguage
            _ = settings.preferredAudioLanguage
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.document != nil else { self?.observing = false; return }
                self.schedulePush(debounce: true)
                self.observeOnce()
            }
        }
    }

    private func schedulePush(debounce: Bool) {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(800)) }
            guard !Task.isCancelled else { return }
            self?.pushLocal()
        }
    }

    private func pushLocal() {
        guard let document else { return }
        let payload: [String: Any] = [
            "debridAPIKeys": settings.debridAPIKeys,
            "debridProvider": settings.debridProvider.rawValue,
            "tmdbAPIKey": settings.tmdbAPIKey,
            "preferredSubtitleLanguage": settings.preferredSubtitleLanguage,
            "preferredAudioLanguage": settings.preferredAudioLanguage,
        ]
        let normalized = Self.normalize(payload)
        guard !NSDictionary(dictionary: normalized).isEqual(to: lastSyncedPayload ?? [:]) else { return }
        lastSyncedPayload = normalized
        document.setData(payload, merge: true)
    }

    private static func normalize(_ data: [String: Any]) -> [String: Any] {
        [
            "debridAPIKeys": (data["debridAPIKeys"] as? [String: String]) ?? [:],
            "debridProvider": (data["debridProvider"] as? String) ?? "",
            "tmdbAPIKey": (data["tmdbAPIKey"] as? String) ?? "",
            "preferredSubtitleLanguage": (data["preferredSubtitleLanguage"] as? String) ?? "",
            "preferredAudioLanguage": (data["preferredAudioLanguage"] as? String) ?? "",
        ]
    }
}
