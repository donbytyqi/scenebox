//
//  NowPlayingController.swift
//  SceneBox
//
//  Created by SpontaneousArray on 04.08.26.
//

#if os(iOS)
import MediaPlayer
import SwiftVLC
import Kingfisher
import UIKit

@MainActor
final class NowPlayingController {
    private let player: Player
    private let title: String
    private var artwork: MPMediaItemArtwork?

    init(player: Player, title: String) {
        self.player = player
        self.title = title
    }

    func begin(artworkURL: URL?) {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.removeTarget(nil)
        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            try? self.player.play()
            self.refresh()
            return .success
        }

        center.pauseCommand.removeTarget(nil)
        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player.pause()
            self.refresh()
            return .success
        }

        center.togglePlayPauseCommand.removeTarget(nil)
        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            self.player.togglePlaybackReasserting()
            self.refresh()
            return .success
        }

        center.skipForwardCommand.removeTarget(nil)
        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] event in
            guard let self, let skip = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            try? self.player.seek(by: .seconds(skip.interval), fast: true)
            self.refresh()
            return .success
        }

        center.skipBackwardCommand.removeTarget(nil)
        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] event in
            guard let self, let skip = event as? MPSkipIntervalCommandEvent else { return .commandFailed }
            try? self.player.seek(by: .seconds(-skip.interval), fast: true)
            self.refresh()
            return .success
        }

        center.changePlaybackPositionCommand.removeTarget(nil)
        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let seek = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            try? self.player.seek(to: .seconds(seek.positionTime))
            self.refresh()
            return .success
        }

        refresh()
        if let artworkURL { loadArtwork(from: artworkURL) }
    }

    func refresh() {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = title
        if let duration = player.duration, duration > .zero {
            info[MPMediaItemPropertyPlaybackDuration] = duration.asSeconds
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime.asSeconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.isPlaying ? 1.0 : 0.0
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func end() {
        let center = MPRemoteCommandCenter.shared()
        let commands: [MPRemoteCommand] = [
            center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
            center.skipForwardCommand, center.skipBackwardCommand,
            center.changePlaybackPositionCommand,
        ]
        for command in commands {
            command.removeTarget(nil)
            command.isEnabled = false
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadArtwork(from url: URL) {
        KingfisherManager.shared.retrieveImage(with: url) { [weak self] result in
            guard case let .success(value) = result else { return }
            let boxed = SendableImage(image: value.image)
            Task { @MainActor in self?.applyArtwork(boxed) }
        }
    }

    private func applyArtwork(_ boxed: SendableImage) {
        artwork = MPMediaItemArtwork(boundsSize: boxed.image.size) { @Sendable _ in boxed.image }
        refresh()
    }
}

private struct SendableImage: @unchecked Sendable {
    let image: UIImage
}
#endif
