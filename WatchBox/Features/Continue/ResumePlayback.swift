//
//  ResumePlayback.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation

extension StreamCoordinator {
    func canResume(_ item: WatchProgress, downloads: DownloadStore) -> Bool {
        guard !item.isFinished else { return false }
        return downloads.isDownloaded(mediaID: item.id, episodeLabel: item.downloadEpisodeLabel)
            || item.lastSource?.debridURL != nil
            || item.lastSource?.torrentStream != nil
    }

    func resume(_ item: WatchProgress, downloads: DownloadStore) {
        let subtitleContext = SubtitleContext(imdbID: item.id, type: item.mediaType,
                                              season: item.season, episode: item.episode)
        let progressContext = WatchProgressContext(
            mediaID: item.id, mediaType: item.mediaType, title: item.title,
            posterURL: item.posterURL, season: item.season, episode: item.episode,
            episodeID: item.episodeID, source: item.lastSource)
        let startAt = Duration.seconds(item.positionSeconds)
        let label = [item.title, item.downloadEpisodeLabel].compactMap { $0 }.joined(separator: " · ")

        if let download = downloads.completedDownload(mediaID: item.id,
                                                      episodeLabel: item.downloadEpisodeLabel) {
            Task {
                guard let url = await downloads.localFileURL(for: download) else { return }
                playLocalFile(at: url, title: label, subtitleContext: subtitleContext,
                              startAt: startAt, progress: progressContext)
            }
        } else if let url = item.lastSource?.debridURL {
            playDebrid(url: url, title: label, backdropURL: item.posterURL,
                       subtitleContext: subtitleContext, startAt: startAt,
                       progress: progressContext)
        } else if let stream = item.lastSource?.torrentStream {
            play(stream, title: label, backdropURL: item.posterURL,
                 subtitleContext: subtitleContext, startAt: startAt,
                 resumeFraction: item.fraction, progress: progressContext)
        }
    }
}
