//
//  CloudSettingsSync.swift
//  SceneBox
//
//  Created by SpontaneousArray on 04.08.26.
//

import CoreFoundation
import Foundation
import FirebaseFirestore
import Observation

/// Mirrors user settings to `users/{uid}/settings/apiKeys` so a second device
/// picks up the same configuration after signing in.
///
/// Two kinds of setting are deliberately kept apart:
///
/// - **User intent** — debrid and metadata keys, Trakt session, stream
///   selection, subtitle/audio languages, custom trackers. These are what make
///   a new device usable without re-entering anything, so they sync.
/// - **Device specifics** — streaming port, storage caps, peer count, Wi-Fi
///   only, player buffer. Your phone should not inherit your Mac's disk limits
///   or listening port, so these stay local.
///
/// The field list below is the single source of truth for what syncs. Reading,
/// applying and the change-detection payload all derive from it, so a field
/// cannot be added to one path and forgotten in another.
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
            // Converted off the main actor into a Sendable form; the raw
            // [String: Any] Firestore hands back cannot cross isolation.
            let remote = Self.remoteValues(snapshot.data() ?? [:])
            Task { @MainActor [weak self] in
                guard let self else { return }
                if remote.isEmpty {
                    self.schedulePush(debounce: false)
                } else {
                    self.apply(remote)
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

    /// Re-reads just the synced Trakt session, ignoring every other field.
    ///
    /// Trakt refresh tokens are single-use: when two devices refresh at once,
    /// the loser is left holding a token the server has already invalidated.
    /// This lets the loser adopt the winner's token instead of signing out.
    /// Returns true when a session was found and applied.
    @discardableResult
    func pullTraktSession() async -> Bool {
        guard let document else { return false }
        guard let snapshot = try? await document.getDocument(), snapshot.exists else { return false }
        let remote = Self.remoteValues(snapshot.data() ?? [:])
        let trakt = remote.filter { $0.key.hasPrefix("trakt") }
        guard !trakt.isEmpty else { return false }
        for field in fields where field.key.hasPrefix("trakt") {
            if let value = trakt[field.key] { field.apply(value) }
        }
        lastSyncedPayload = currentPayload()
        return true
    }

    // MARK: Remote → local

    private func apply(_ remote: [String: RemoteValue]) {
        for field in fields {
            if let value = remote[field.key] { field.apply(value) }
        }
        lastSyncedPayload = currentPayload()
    }

    // MARK: Local → remote

    private func startObservingLocalChanges() {
        guard !observing else { return }
        observing = true
        observeOnce()
    }

    private func observeOnce() {
        withObservationTracking {
            // Reading every synced field here is what registers the
            // observation; a field absent from this loop would never push.
            for field in fields { _ = field.local() }
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
        let payload = currentPayload()
        guard !NSDictionary(dictionary: payload).isEqual(to: lastSyncedPayload ?? [:]) else { return }
        lastSyncedPayload = payload
        document.setData(payload, merge: true)
    }

    private func currentPayload() -> [String: Any] {
        var out: [String: Any] = [:]
        for field in fields {
            if let value = field.local() { out[field.key] = value.firestoreValue }
        }
        return out
    }

    // MARK: Synced fields

    /// One synced setting: how to read it locally and how to write a remote
    /// value back. Both are expressed in `RemoteValue` so the field list stays
    /// Sendable-safe and comparable.
    private struct SyncedField {
        let key: String
        let local: () -> RemoteValue?
        let apply: (RemoteValue) -> Void
    }

    private var fields: [SyncedField] {
        let settings = self.settings

        func string(
            _ key: String,
            _ read: @escaping () -> String,
            _ write: @escaping (String) -> Void
        ) -> SyncedField {
            SyncedField(key: key,
                        local: { .string(read()) },
                        apply: { if case .string(let value) = $0 { write(value) } })
        }

        func flag(
            _ key: String,
            _ read: @escaping () -> Bool,
            _ write: @escaping (Bool) -> Void
        ) -> SyncedField {
            SyncedField(key: key,
                        local: { .bool(read()) },
                        apply: { if case .bool(let value) = $0 { write(value) } })
        }

        func number(
            _ key: String,
            _ read: @escaping () -> Double,
            _ write: @escaping (Double) -> Void
        ) -> SyncedField {
            SyncedField(key: key,
                        local: { .number(read()) },
                        apply: { if case .number(let value) = $0 { write(value) } })
        }

        func stringMap(
            _ key: String,
            _ read: @escaping () -> [String: String],
            _ write: @escaping ([String: String]) -> Void
        ) -> SyncedField {
            SyncedField(key: key,
                        local: { .stringMap(read()) },
                        apply: { if case .stringMap(let value) = $0 { write(value) } })
        }

        /// Sets are sorted on the way out. Without this the iteration order
        /// varies per launch, so the change-detection comparison would see a
        /// difference and push on every start.
        func stringSet(
            _ key: String,
            _ read: @escaping () -> [String],
            _ write: @escaping ([String]) -> Void
        ) -> SyncedField {
            SyncedField(key: key,
                        local: { .strings(read().sorted()) },
                        apply: { if case .strings(let value) = $0 { write(value) } })
        }

        return [
            // MARK: Keys and accounts
            stringMap("debridAPIKeys",
                      { settings.debridAPIKeys },
                      { settings.debridAPIKeys = $0 }),
            string("debridProvider",
                   { settings.debridProvider.rawValue },
                   { if let provider = DebridProvider(rawValue: $0) { settings.debridProvider = provider } }),
            string("tmdbAPIKey",
                   { settings.tmdbAPIKey },
                   { settings.tmdbAPIKey = $0 }),
            string("omdbAPIKey",
                   { settings.omdbAPIKey },
                   { settings.omdbAPIKey = $0 }),

            // MARK: Trakt session
            // Synced so a second device is already signed in. Refresh tokens
            // rotate, so `pullTraktSession()` exists to re-sync after a race.
            string("traktAccessToken",
                   { settings.traktAccessToken },
                   { settings.traktAccessToken = $0 }),
            string("traktRefreshToken",
                   { settings.traktRefreshToken },
                   { settings.traktRefreshToken = $0 }),
            number("traktTokenExpiry",
                   { settings.traktTokenExpiry },
                   { settings.traktTokenExpiry = $0 }),
            string("traktUsername",
                   { settings.traktUsername },
                   { settings.traktUsername = $0 }),
            flag("traktSyncEnabled",
                 { settings.traktSyncEnabled },
                 { settings.traktSyncEnabled = $0 }),
            string("traktBackfillUsername",
                   { settings.traktBackfillUsername },
                   { settings.traktBackfillUsername = $0 }),

            // MARK: Stream selection
            string("releaseSort",
                   { settings.releaseSort.rawValue },
                   { if let sort = ReleaseSort(rawValue: $0) { settings.releaseSort = sort } }),
            string("preferredResolution",
                   { settings.preferredResolution },
                   { settings.preferredResolution = $0 }),
            stringSet("excludedQualities",
                      { settings.excludedQualities.map(\.rawValue) },
                      { settings.excludedQualities = Set($0.compactMap(QualityFilter.init(rawValue:))) }),
            stringSet("enabledSources",
                      { settings.enabledSources.map(\.rawValue) },
                      { settings.enabledSources = Set($0.compactMap(StreamProvider.init(rawValue:))) }),
            flag("autoSelectSource",
                 { settings.autoSelectSource },
                 { settings.autoSelectSource = $0 }),
            flag("extraSourceProviders",
                 { settings.extraSourceProviders },
                 { settings.extraSourceProviders = $0 }),
            flag("shareDebridKeyWithCommunitySources",
                 { settings.shareDebridKeyWithCommunitySources },
                 { settings.shareDebridKeyWithCommunitySources = $0 }),
            string("stremthruHost",
                   { settings.stremthruHost },
                   { settings.stremthruHost = $0 }),

            // MARK: Playback and network preferences
            string("preferredSubtitleLanguage",
                   { settings.preferredSubtitleLanguage },
                   { settings.preferredSubtitleLanguage = $0 }),
            string("preferredAudioLanguage",
                   { settings.preferredAudioLanguage },
                   { settings.preferredAudioLanguage = $0 }),
            number("subtitleScale",
                   { settings.subtitleScale },
                   { settings.subtitleScale = $0 }),
            string("customTrackers",
                   { settings.customTrackers },
                   { settings.customTrackers = $0 }),
        ]
    }

    // MARK: Wire values

    /// A Firestore value reduced to the handful of shapes these settings use,
    /// so it can cross an isolation boundary and be matched by type on arrival.
    ///
    /// `nonisolated` because the project's default actor isolation would
    /// otherwise make this type main-actor bound, and it has to be built on
    /// Firestore's listener queue.
    private nonisolated enum RemoteValue: Sendable {
        case string(String)
        case bool(Bool)
        case number(Double)
        case strings([String])
        case stringMap([String: String])

        init?(_ value: Any) {
            switch value {
            case let value as String:
                self = .string(value)
            case let value as [String]:
                self = .strings(value)
            case let value as [String: String]:
                self = .stringMap(value)
            case let value as NSNumber:
                // `as? Bool` succeeds for any NSNumber, so the CoreFoundation
                // type is the only reliable way to tell a boolean from a
                // number. Getting this wrong silently drops the field, because
                // a `.number` never matches a flag's `.bool` case.
                if CFGetTypeID(value) == CFBooleanGetTypeID() {
                    self = .bool(value.boolValue)
                } else {
                    self = .number(value.doubleValue)
                }
            default:
                return nil
            }
        }

        var firestoreValue: Any {
            switch self {
            case .string(let value): value
            case .bool(let value): value
            case .number(let value): value
            case .strings(let value): value
            case .stringMap(let value): value
            }
        }
    }

    nonisolated private static func remoteValues(_ data: [String: Any]) -> [String: RemoteValue] {
        data.compactMapValues(RemoteValue.init)
    }
}
