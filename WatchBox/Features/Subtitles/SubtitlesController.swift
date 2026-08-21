//
//  SubtitlesController.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation
import Observation
import SwiftVLC

@MainActor
@Observable
final class SubtitlesController {
    private(set) var available: [SubtitleTrack] = []
    private(set) var selectedID: String?
    private(set) var embeddedID: String?
    private(set) var externalTrackIDs: Set<String> = []
    private(set) var isLoading = false

    @ObservationIgnored private let provider = SubtitlesProvider()
    @ObservationIgnored private var applyTask: Task<Void, Never>?
    @ObservationIgnored private var loaded = false
    @ObservationIgnored private var preferred = ""
    @ObservationIgnored private var preferenceSatisfied = false

    func load(context: SubtitleContext, preferred: String, player: Player) {
        guard !loaded else { return }
        loaded = true
        self.preferred = preferred

        syncEmbedded(on: player)

        isLoading = true
        Task {
            async let fetched = provider.subtitles(imdbID: context.imdbID, type: context.type,
                                                   season: context.season, episode: context.episode)
            await awaitEmbeddedPreference(on: player)
            available = await fetched
            isLoading = false

            guard !preferenceSatisfied, !preferred.isEmpty else { return }
            if let match = available.first(where: { $0.languageCode == preferred }) {
                apply(match, on: player)
            } else {
                preferenceSatisfied = true
            }
        }
    }

    func syncEmbedded(on player: Player) {
        guard !preferenceSatisfied else { return }

        guard !preferred.isEmpty else {
            if player.selectedSubtitleTrack != nil { player.selectedSubtitleTrack = nil }
            return
        }

        guard let match = embeddedTracks(of: player).first(where: matchesPreferred) else { return }
        applyTask?.cancel()
        player.selectedSubtitleTrack = match
        selectedID = nil
        embeddedID = match.id
        preferenceSatisfied = true
    }

    private func awaitEmbeddedPreference(on player: Player) async {
        guard !preferred.isEmpty else { return }

        for _ in 0..<16 {                                   // ~8s of grace while tracks load
            if preferenceSatisfied { return }
            if let match = embeddedTracks(of: player).first(where: matchesPreferred) {
                player.selectedSubtitleTrack = match
                selectedID = nil
                embeddedID = match.id
                preferenceSatisfied = true
                return
            }
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    func apply(_ track: SubtitleTrack?, on player: Player) {
        applyTask?.cancel()
        preferenceSatisfied = true
        embeddedID = nil
        guard let track else {
            player.selectedSubtitleTrack = nil
            selectedID = nil
            return
        }
        selectedID = track.id
        applyTask = Task {
            guard let localURL = try? await provider.download(track) else {
                if !Task.isCancelled { selectedID = nil }
                return
            }
            guard !Task.isCancelled else { return }

            let before = Set(player.subtitleTracks.map(\.id))
            try? player.addExternalTrack(from: localURL, type: .subtitle, select: true)

            for _ in 0..<15 {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                if let added = player.subtitleTracks.first(where: {
                    !before.contains($0.id) && $0.isSelected
                }) {
                    externalTrackIDs.insert(added.id)
                    return
                }
            }
        }
    }

    func selectEmbedded(_ track: Track, on player: Player) {
        applyTask?.cancel()
        preferenceSatisfied = true
        selectedID = nil
        embeddedID = track.id
        player.selectedSubtitleTrack = track
    }

    func embeddedTracks(of player: Player) -> [Track] {
        var seen = Set<String>()
        return player.subtitleTracks.filter {
            !externalTrackIDs.contains($0.id) && seen.insert($0.id).inserted
        }
    }

    private func matchesPreferred(_ track: Track) -> Bool {
        guard !preferred.isEmpty else { return false }
        let name = SubtitleLanguage.displayName(for: preferred).lowercased()  // e.g. "english"
        let lang = (track.language ?? "").lowercased()
        let label = track.name.lowercased()
        for needle in [preferred.lowercased(), name] where !needle.isEmpty {
            if !lang.isEmpty, lang.contains(needle) || needle.contains(lang) { return true }
            if !name.isEmpty, label.contains(name) { return true }
        }
        return false
    }

    var byLanguage: [(language: String, tracks: [SubtitleTrack])] {
        let groups = Dictionary(grouping: available, by: \.languageName)
        return groups
            .map { (language: $0.key, tracks: $0.value) }
            .sorted { lhs, rhs in
                let l = available.firstIndex { $0.languageName == lhs.language } ?? 0
                let r = available.firstIndex { $0.languageName == rhs.language } ?? 0
                return l < r
            }
    }
}
