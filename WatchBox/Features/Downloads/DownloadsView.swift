//
//  DownloadsView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

import SwiftUI

struct DownloadsView: View {
    @Environment(DownloadStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var streamer = StreamCoordinator()
    @State private var pendingDelete: Download?

    var body: some View {
        Group {
            if store.downloads.isEmpty {
                EmptyStateView(
                    systemImage: "arrow.down.circle",
                    title: "No downloads",
                    message: "Pick a title and tap Download to keep it on this device.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    #if os(tvOS)
                    .frame(minHeight: 500)   // hosted in Library's ScrollView
                    #endif
            } else {
                #if os(tvOS)
                LazyVStack(spacing: 12) {
                    ForEach(store.downloads) { download in
                        DownloadRow(
                            download: download,
                            onPrimary: { primaryAction(for: download) },
                            onDelete: { pendingDelete = download })
                    }
                }
                .focusSection()
                #else
                List {
                    ForEach(store.downloads) { download in
                        DownloadRow(
                            download: download,
                            onPrimary: { primaryAction(for: download) },
                            onDelete: { pendingDelete = download })
                        .listRowBackground(Theme.background)
                    }
                }
                .listStyle(.plain)
                .hideScrollBackground()
                .refreshable { store.refreshDiskUsage() }
                #endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .fullScreenCover(item: Binding(get: { streamer.target },
                                       set: { if $0 == nil { streamer.stop() } })) { target in
            PlaybackScreen(url: target.url, title: target.title,
                           stats: nil, subtitleContext: target.subtitleContext,
                           startAt: target.startPosition,
                           progress: target.progress,
                           onClose: streamer.stop)
                .environment(settings)
        }
        .alert("Delete download?", isPresented: Binding(get: { pendingDelete != nil },
                                                        set: { if !$0 { pendingDelete = nil } })) {
            Button("Delete", role: .destructive) {
                if let pendingDelete { store.remove(pendingDelete) }
                pendingDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("“\(pendingDelete?.record.title ?? "")” and its files will be removed from this device.")
        }
    }

    private func primaryAction(for download: Download) {
        switch download.phase {
        case .completed:
            Task {
                guard let url = await store.localFileURL(for: download) else { return }
                let title = [download.record.title, download.record.episodeLabel]
                    .compactMap { $0 }.joined(separator: " · ")
                let context = download.record.watchProgressContext
                streamer.playLocalFile(at: url, title: title,
                                       subtitleContext: download.record.subtitleContext,
                                       startAt: resumePosition(for: context),
                                       progress: context)
            }
        case .downloading, .resolving:
            store.pause(download)
        case .paused, .failed:
            store.resume(download)
        }
    }

    private func resumePosition(for context: WatchProgressContext?) -> Duration {
        guard let context,
              let saved = WatchProgressStore.shared.progress(for: context.mediaID),
              !saved.isFinished, saved.episodeID == context.episodeID
        else { return .zero }
        return .seconds(saved.positionSeconds)
    }
}

private struct DownloadRow: View {
    let download: Download
    let onPrimary: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: rowSpacing) {
            PosterImage(url: download.record.posterURL, cornerRadius: 6)
                .frame(width: posterWidth)

            VStack(alignment: .leading, spacing: 6) {
                Text(download.record.title)
                    .font(titleFont)
                    .lineLimit(1)

                Text(download.record.subtitleLine)
                    .font(subtitleFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if download.phase != .completed {
                    ProgressView(value: download.progress)
                        .tint(download.phase == .failed ? .red : Theme.accent)
                }

                if let size = download.sizeProgressText {
                    Text(size)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Text(download.statusText)
                    .foregroundStyle(download.phase == .failed ? .red : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .font(metaFont)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            actionButtons
        }
        .padding(.vertical, rowSpacing / 2)
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var actionButtons: some View {
        #if os(tvOS)
        HStack(spacing: 16) {
            Button(action: onPrimary) { Image(systemName: primaryIcon) }
                .tint(Theme.accent)
            Button(action: onDelete) { Image(systemName: "trash") }
                .tint(.red)
        }
        .buttonStyle(.bordered)
        .font(.title3)
        #else
        VStack(spacing: 10) {
            Button(action: onPrimary) {
                Image(systemName: primaryIcon)
                    .font(.system(size: 33))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            Button(action: onDelete) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 29))
                    .foregroundStyle(.red.opacity(0.9))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        #endif
    }

    #if os(tvOS)
    private var posterWidth: CGFloat { 130 }
    private var rowSpacing: CGFloat { 28 }
    private var titleFont: Font { .title3.weight(.semibold) }
    private var subtitleFont: Font { .callout }
    private var metaFont: Font { .callout.monospacedDigit() }
    #else
    private var posterWidth: CGFloat { 54 }
    private var rowSpacing: CGFloat { 12 }
    private var titleFont: Font { .subheadline.weight(.semibold) }
    private var subtitleFont: Font { .caption }
    private var metaFont: Font { .caption2.monospacedDigit() }
    #endif

    private var primaryIcon: String {
        switch download.phase {
        case .completed: "play.circle.fill"
        case .downloading, .resolving: "pause.circle.fill"
        case .paused, .failed: "arrow.down.circle.fill"
        }
    }
}
