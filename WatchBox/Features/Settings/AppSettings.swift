//
//  AppSettings.swift
//  SceneBox
//
//  Created by SpontaneousArray on 05.08.26.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class AppSettings {
    static let shared = AppSettings()

    // MARK: Stream quality

    var excludedQualities: Set<QualityFilter> = [.cam, .scr] {
        didSet { persist(Array(excludedQualities.map(\.rawValue)), .excludedQualities) }
    }

    var releaseSort: ReleaseSort = .seeders {
        didSet { persist(releaseSort.rawValue, .releaseSort) }
    }

    var preferredResolution: String = "1080p" {
        didSet { persist(preferredResolution, .preferredResolution) }
    }

    var extraSourceProviders = false {
        didSet { persist(extraSourceProviders, .extraSourceProviders) }
    }

    var streamProviderFallbacks: [String] {
        extraSourceProviders ? ["https://thepiratebay-plus.strem.fun"] : []
    }

    var enabledSources: Set<StreamProvider> = [.torrentio, .stremthru] {
        didSet { persist(Array(enabledSources.map(\.rawValue)), .enabledSources) }
    }

    var streamSourceBases: [String] {
        var bases: [String] = []
        for provider in StreamProvider.queryOrder where enabledSources.contains(provider) {
            if let base = provider.baseURL(debrid: debridProvider, key: debridAPIKey,
                                           torrentioConfig: torrentioConfig,
                                           shareKeyWithCommunityHosts: shareDebridKeyWithCommunitySources,
                                           stremthruHost: stremthruHost) {
                bases.append(base)
            }
        }
        bases.append(contentsOf: streamProviderFallbacks)
        if bases.isEmpty { bases = ["https://torrentio.strem.fun"] }
        return bases
    }

    var autoSelectSource = false {
        didSet { persist(autoSelectSource, .autoSelectSource) }
    }

    // MARK: Appearance

    let accentColorHex: String = Theme.defaultAccentHex

    var accentColor: Color { Color(hex: accentColorHex) }

    // MARK: Debrid

    var debridProvider: DebridProvider = .none {
        didSet { persist(debridProvider.rawValue, .debridProvider) }
    }

    var debridAPIKeys: [String: String] = [:] {
        didSet {
            let data = try? JSONEncoder().encode(debridAPIKeys)
            KeychainStore.setData(debridAPIKeys.isEmpty ? nil : data, for: Key.debridAPIKeys.rawValue)
        }
    }

    var shareDebridKeyWithCommunitySources = false {
        didSet { persist(shareDebridKeyWithCommunitySources, .shareDebridKeyWithCommunitySources) }
    }

    var stremthruHost: String = StreamProvider.defaultStremthruHost {
        didSet { persist(stremthruHost, .stremthruHost) }
    }

    var debridAPIKey: String {
        get { debridAPIKeys[debridProvider.rawValue] ?? "" }
        set { debridAPIKeys[debridProvider.rawValue] = newValue }
    }

    var debridEnabled: Bool { debridProvider.requiresKey && !debridAPIKey.isEmpty }

    var hasRealDebridKey: Bool {
        !(debridAPIKeys[DebridProvider.realDebrid.rawValue] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Cast metadata

    var tmdbAPIKey: String = "" {
        didSet { KeychainStore.setString(tmdbAPIKey, for: Key.tmdbAPIKey.rawValue) }
    }

    // MARK: Playback

    nonisolated static let subtitleScaleOptions: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var subtitleScale: Double = 1.0 {
        didSet { persist(subtitleScale, .subtitleScale) }
    }

    var preferredAudioLanguage: String = "en" {
        didSet { persist(preferredAudioLanguage, .preferredAudioLanguage) }
    }

    nonisolated static let audioLanguageOptions: [(code: String, name: String)] = [
        ("", "Original"), ("en", "English"), ("es", "Spanish"), ("fr", "French"),
        ("de", "German"), ("it", "Italian"), ("pt", "Portuguese"), ("ja", "Japanese"),
        ("ko", "Korean"), ("zh", "Chinese"), ("ru", "Russian"), ("hi", "Hindi"),
        ("ar", "Arabic"), ("tr", "Turkish"), ("nl", "Dutch"), ("pl", "Polish"),
    ]

    var preferredSubtitleLanguage: String = SubtitleLanguage.deviceDefault.code {
        didSet { persist(preferredSubtitleLanguage, .preferredSubtitleLanguage) }
    }

    var networkCacheMilliseconds: Int = 3000 {
        didSet { persist(networkCacheMilliseconds, .networkCache) }
    }

    var fillScreen = false {
        didSet { persist(fillScreen, .fillScreen) }
    }

    // MARK: Storage

    var storageCapBytes: Int64 = 0 {
        didSet { persist(storageCapBytes, .storageCap) }
    }

    var streamCacheLimitGB: Int = 4 {
        didSet { persist(streamCacheLimitGB, .streamCacheLimit) }
    }

    var streamCacheLimitBytes: Int64 { Int64(streamCacheLimitGB) * 1_073_741_824 }

    static let streamCacheOptions = [0, 2, 4, 8, 16]

    // MARK: Network

    var maxPeers: Int = 80 {
        didSet { persist(maxPeers, .maxPeers) }
    }

    var streamingPort: Int = AppSettings.defaultStreamingPort {
        didSet {
            if !AppSettings.streamingPortRange.contains(streamingPort) {
                streamingPort = AppSettings.defaultStreamingPort   // re-enters didSet with a valid value
                return
            }
            persist(streamingPort, .streamingPort)
        }
    }
    nonisolated static let defaultStreamingPort = 8888
    nonisolated static let streamingPortRange = 1024...65535

    var wifiOnly = false {
        didSet { persist(wifiOnly, .wifiOnly) }
    }

    var customTrackers: String = "" {
        didSet { persist(customTrackers, .customTrackers) }
    }

    var customTrackerURLs: [URL] {
        customTrackers
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap(URL.init(string:))
    }

    // MARK: Derived

    var torrentioConfig: String {
        var parts: [String] = ["sort=\(releaseSort.torrentioValue)"]
        if !excludedQualities.isEmpty {
            let filters = QualityFilter.allCases
                .filter(excludedQualities.contains)
                .map(\.rawValue)
                .joined(separator: ",")
            parts.append("qualityfilter=\(filters)")
        }
        let trimmedKey = debridAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if let key = debridProvider.torrentioKey, !trimmedKey.isEmpty {
            parts.append("\(key)=\(trimmedKey)")
        }
        return parts.joined(separator: "|")
    }

    // MARK: Persistence

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let raw = defaults.array(forKey: Key.excludedQualities.rawValue) as? [String] {
            excludedQualities = Set(raw.compactMap(QualityFilter.init(rawValue:)))
        }
        if let raw = defaults.string(forKey: Key.releaseSort.rawValue),
           let sort = ReleaseSort(rawValue: raw) {
            releaseSort = sort
        }
        if let value = defaults.string(forKey: Key.preferredResolution.rawValue) {
            preferredResolution = value
        }
        if defaults.object(forKey: Key.subtitleScale.rawValue) != nil {
            let stored = defaults.double(forKey: Key.subtitleScale.rawValue)
            subtitleScale = Self.subtitleScaleOptions
                .min(by: { abs($0 - stored) < abs($1 - stored) }) ?? 1.0
        }
        if let stored = defaults.string(forKey: Key.preferredSubtitleLanguage.rawValue) {
            preferredSubtitleLanguage = stored
        }
        if let stored = defaults.string(forKey: Key.preferredAudioLanguage.rawValue) {
            preferredAudioLanguage = stored
        }
        if defaults.object(forKey: Key.networkCache.rawValue) != nil {
            networkCacheMilliseconds = defaults.integer(forKey: Key.networkCache.rawValue)
        }
        fillScreen = defaults.bool(forKey: Key.fillScreen.rawValue)
        storageCapBytes = Int64(defaults.integer(forKey: Key.storageCap.rawValue))
        if defaults.object(forKey: Key.streamCacheLimit.rawValue) != nil {
            streamCacheLimitGB = defaults.integer(forKey: Key.streamCacheLimit.rawValue)
        }
        if defaults.object(forKey: Key.maxPeers.rawValue) != nil {
            maxPeers = defaults.integer(forKey: Key.maxPeers.rawValue)
        }
        if defaults.object(forKey: Key.streamingPort.rawValue) != nil {
            let stored = defaults.integer(forKey: Key.streamingPort.rawValue)
            streamingPort = Self.streamingPortRange.contains(stored) ? stored : Self.defaultStreamingPort
        }
        wifiOnly = defaults.bool(forKey: Key.wifiOnly.rawValue)
        customTrackers = defaults.string(forKey: Key.customTrackers.rawValue) ?? ""
        if let raw = defaults.string(forKey: Key.debridProvider.rawValue),
           let provider = DebridProvider(rawValue: raw) {
            debridProvider = provider
        }
        if let data = KeychainStore.data(for: Key.debridAPIKeys.rawValue),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            debridAPIKeys = stored
        } else if let stored = defaults.dictionary(forKey: Key.debridAPIKeys.rawValue) as? [String: String] {
            debridAPIKeys = stored                                  // → Keychain via didSet
        } else if let legacy = defaults.string(forKey: Key.debridAPIKey.rawValue), !legacy.isEmpty {
            debridAPIKeys = [debridProvider.rawValue: legacy]      // old single-key slot
        }
        defaults.removeObject(forKey: Key.debridAPIKeys.rawValue)
        defaults.removeObject(forKey: Key.debridAPIKey.rawValue)
        if let stored = KeychainStore.string(for: Key.tmdbAPIKey.rawValue) {
            tmdbAPIKey = stored
        } else if let stored = defaults.string(forKey: Key.tmdbAPIKey.rawValue), !stored.isEmpty {
            tmdbAPIKey = stored                                     // → Keychain via didSet
        }
        defaults.removeObject(forKey: Key.tmdbAPIKey.rawValue)
        shareDebridKeyWithCommunitySources = defaults.bool(forKey: Key.shareDebridKeyWithCommunitySources.rawValue)
        if let host = defaults.string(forKey: Key.stremthruHost.rawValue), !host.isEmpty {
            stremthruHost = host
        }
        extraSourceProviders = defaults.bool(forKey: Key.extraSourceProviders.rawValue)
        autoSelectSource = defaults.bool(forKey: Key.autoSelectSource.rawValue)
        if let raw = defaults.array(forKey: Key.enabledSources.rawValue) as? [String] {
            enabledSources = Set(raw.compactMap(StreamProvider.init(rawValue:)))
        }
    }

    private enum Key: String {
        case excludedQualities, releaseSort, preferredResolution, accentColor
        case subtitleScale, preferredSubtitleLanguage, preferredAudioLanguage
        case networkCache, fillScreen
        case storageCap, streamCacheLimit
        case maxPeers, streamingPort, wifiOnly, customTrackers
        case debridProvider, debridAPIKey, debridAPIKeys
        case tmdbAPIKey
        case extraSourceProviders
        case autoSelectSource
        case enabledSources
        case shareDebridKeyWithCommunitySources, stremthruHost
    }

    private func persist(_ value: Any?, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }
}
