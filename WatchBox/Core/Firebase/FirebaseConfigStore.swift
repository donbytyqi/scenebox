//
//  FirebaseConfigStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 11.10.26.
//

import Foundation
import Observation
import FirebaseCore

/// Owns where the app's Firebase configuration comes from.
///
/// SceneBox ships without a `GoogleService-Info.plist`, so there are two ways to
/// get one: bundle your own at build time, or import one at runtime from
/// Settings. An imported plist is copied into Application Support so it keeps
/// working on later launches without the security-scoped access that the file
/// picker hands out for one session only.
///
/// Firebase cannot be reconfigured once `FirebaseApp.configure` has run, so
/// importing or removing a plist only takes effect after a relaunch.
@MainActor
@Observable
final class FirebaseConfigStore {
    static let shared = FirebaseConfigStore()

    enum Source: Equatable {
        /// No plist anywhere: the app runs in guest/local mode only.
        case none
        /// A `GoogleService-Info.plist` compiled into the app bundle.
        case bundled
        /// A plist the user imported from Settings.
        case imported
    }

    enum ImportError: LocalizedError {
        case unreadable
        case notAPlist
        case missingKeys([String])
        case bundleMismatch(expected: String, found: String)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return "That file couldn't be read. Try downloading it again from the Firebase console."
            case .notAPlist:
                return "That isn't a property list. Pick the GoogleService-Info.plist you downloaded."
            case .missingKeys(let keys):
                return "That plist is missing \(keys.joined(separator: ", ")). Make sure you downloaded it from a Firebase iOS app."
            case .bundleMismatch(let expected, let found):
                return "That plist is for bundle ID “\(found)”, but SceneBox is “\(expected)”. Add an iOS app with the matching bundle ID in the Firebase console and download its plist."
            }
        }
    }

    private(set) var source: Source
    /// True when the on-disk plist changed this session but Firebase is still
    /// running on the old one.
    private(set) var needsRelaunch = false
    private(set) var importError: String?

    private init() {
        source = Self.configureFirebase()
    }

    var isConfigured: Bool { source != .none }

    var hasImportedConfig: Bool {
        guard let url = Self.importedURL else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Launch

    /// Configures the default Firebase app, preferring an imported plist over a
    /// bundled one. Returns the source that won.
    ///
    /// Built on `FirebaseOptions(contentsOfFile:)` rather than
    /// `FirebaseApp.configure()` because the latter calls `fatalError` when the
    /// plist is missing or malformed — which is exactly the state a user who
    /// hasn't set up Firebase yet is in.
    nonisolated static func configureFirebase() -> Source {
        let manager = FileManager.default

        if let url = importedURL,
           manager.fileExists(atPath: url.path),
           let options = FirebaseOptions(contentsOfFile: url.path) {
            FirebaseApp.configure(options: options)
            return .imported
        }

        if let url = bundledURL, let options = FirebaseOptions(contentsOfFile: url.path) {
            FirebaseApp.configure(options: options)
            return .bundled
        }

        return .none
    }

    nonisolated static var bundledURL: URL? {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist")
    }

    /// `~/Library/Application Support/Firebase/GoogleService-Info.plist`
    /// (inside the app container on iOS and Mac Catalyst).
    nonisolated static var importedURL: URL? {
        // `create: true` because Application Support does not exist in a fresh
        // container, and `url(for:)` throws rather than returning a path.
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return base
            .appendingPathComponent("Firebase", isDirectory: true)
            .appendingPathComponent("GoogleService-Info.plist", isDirectory: false)
    }

    // MARK: - Import

    func importConfig(from url: URL) {
        importError = nil

        // The picker hands back a URL that is only readable for the duration of
        // the security scope. Without this the read fails on a sandboxed build.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        do {
            guard let data = try? Data(contentsOf: url) else { throw ImportError.unreadable }
            try Self.validate(data)

            guard let destination = Self.importedURL else { throw ImportError.unreadable }
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: destination, options: .atomic)

            needsRelaunch = true
        } catch {
            importError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func removeImportedConfig() {
        importError = nil
        guard let url = Self.importedURL else { return }
        try? FileManager.default.removeItem(at: url)
        needsRelaunch = true
    }

    func clearImportError() { importError = nil }

    /// `fileImporter` reports its own failures (a dismissed picker, an
    /// unreadable selection) separately from the import itself.
    func reportPickerFailure(_ error: Error) {
        importError = "Couldn't open that file: \(error.localizedDescription)"
    }

    private nonisolated static func validate(_ data: Data) throws {
        guard let plist = try? PropertyListSerialization
            .propertyList(from: data, format: nil) as? [String: Any] else {
            throw ImportError.notAPlist
        }

        // The keys FirebaseCore reads to build its options. Missing any of them
        // means this isn't a usable GoogleService-Info.plist.
        let required = ["GOOGLE_APP_ID", "GCM_SENDER_ID", "API_KEY", "PROJECT_ID"]
        let missing = required.filter { (plist[$0] as? String)?.isEmpty != false }
        guard missing.isEmpty else { throw ImportError.missingKeys(missing) }

        // Firebase Auth rejects a plist whose BUNDLE_ID doesn't match the app.
        if let found = plist["BUNDLE_ID"] as? String,
           let expected = Bundle.main.bundleIdentifier,
           found != expected {
            throw ImportError.bundleMismatch(expected: expected, found: found)
        }
    }
}
