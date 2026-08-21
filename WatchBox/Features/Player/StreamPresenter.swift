//
//  StreamPresenter.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import SwiftUI
import Kingfisher

struct StreamPlayerContainer: View {
    let streamer: StreamCoordinator
    @Environment(AppSettings.self) private var settings

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let target = streamer.target {
                PlaybackScreen(
                    url: target.url,
                    title: target.title,
                    stats: target.showsTorrentStats ? streamer.stats : nil,
                    subtitleContext: target.subtitleContext,
                    episodes: streamer.episodePlaylist,
                    startAt: target.startPosition,
                    progress: target.progress,
                    artworkURL: streamer.backdropURL,
                    originalAudioLanguage: target.originalAudioLanguage,
                    onClose: streamer.stop
                )
                .id(target.url)   // rebuild the player for a new episode's stream
                .environment(settings)
            } else {
                PreparingPlayerView(
                    backdropURL: streamer.backdropURL,
                    logoURL: streamer.logoURL,
                    title: streamer.title,
                    progress: streamer.bufferProgress,
                    status: streamer.preparingStatus,
                    error: streamer.errorMessage,
                    onClose: streamer.stop
                )
            }
        }
        .animation(nil, value: streamer.target?.url)
        #if DEBUG
        .overlay(alignment: .topTrailing) { DiagnosticsOverlay() }
        #endif
    }
}

#if DEBUG
private struct DiagnosticsOverlay: View {
    private var diag = TorrentDiagnostics.shared

    var body: some View {
        if let s = diag.latest {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(s.appState)\(s.deviceLocked ? " LOCKED" : "") · \(s.network) · \(s.torrentState)")
                Text("peers \(s.peers) (\(s.seeds) seed) conns \(s.connections) cand \(s.candidates) known \(s.listPeers)")
                Text("rate \(Int(s.downloadRate) / 1024) KB/s · att \(s.attempts) fail \(s.connectFailures) · dht \(s.dhtNodes)")
                Text("t=\(Int(s.playerSeconds))s · head \(s.playheadMB)MB · win \(s.window)")
                if let top = s.disconnectReasons.max(by: { $0.value < $1.value }) {
                    Text("\(top.key) ×\(top.value)").lineLimit(1)
                }
            }
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.green)
            .padding(6)
            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 6))
            .padding(.top, 40)
            .padding(.trailing, 12)
            .allowsHitTesting(false)
        }
    }
}
#endif

private struct PreparingPlayerView: View {
    let backdropURL: URL?
    let logoURL: URL?
    let title: String
    let progress: Double?
    let status: String?
    let error: String?
    let onClose: () -> Void

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()

            if error != nil {
                errorCard(width: 360)
            } else {
                VStack(spacing: 28) {
                    titleArt
                    VStack(spacing: 14) {
                        BufferBar(progress: progress)
                            .frame(maxWidth: 300)
                        if let status {
                            Text(status)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .contentTransition(.numericText())
                                .animation(.default, value: status)
                        }
                    }
                }
                .padding(.horizontal, 40)
                .shadow(color: .black.opacity(0.6), radius: 14, y: 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topLeading) { closeButton }
        .preferredColorScheme(.dark)
        .hideStatusBarCompat()
        #if os(tvOS)
        .onExitCommand(perform: onClose)
        #endif
    }

    private var backdrop: some View {
        Color.clear
            .overlay {
                KFImage(backdropURL)
                    .resizable()
                    .fade(duration: 0.25)
                    .placeholder { Color.black }
                    .scaledToFill()
            }
            .clipped()
            .overlay(Color.black.opacity(0.45))
            .overlay(
                RadialGradient(colors: [.black.opacity(0.55), .clear],
                               center: .center, startRadius: 0, endRadius: 380)
            )
    }

    @ViewBuilder
    private var titleArt: some View {
        if let logoURL {
            KFImage(logoURL)
                .resizable()
                .fade(duration: 0.2)
                .placeholder { titleText }
                .scaledToFit()
                .frame(maxWidth: 360, maxHeight: 160)
        } else {
            titleText
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: 34, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(3)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: 340)
    }

    private func errorCard(width: CGFloat) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text(error ?? "")
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            Button("Close", action: onClose)
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.black)
        }
        .frame(maxWidth: min(width, 360))
    }

    private var closeButton: some View {
        #if os(tvOS)
        Button(action: onClose) { Image(systemName: "xmark") }
            .buttonStyle(TVCircleButtonStyle(diameter: 46))
            .padding(.leading, 50)
            .padding(.top, 40)
        #else
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(.black.opacity(0.45), in: Circle())
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        #endif
    }
}

private struct BufferBar: View {
    let progress: Double?
    private let height: CGFloat = 8

    @State private var sweep = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Capsule()
                .fill(.white.opacity(0.28))
                .overlay(alignment: .leading) {
                    if let progress {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: max(height, w * CGFloat(max(0, min(1, progress)))))
                            .animation(.easeOut(duration: 0.4), value: progress)
                    } else {
                        Capsule()
                            .fill(Theme.accent)
                            .frame(width: w * 0.34)
                            .offset(x: sweep ? w : -w * 0.34)
                            .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false),
                                       value: sweep)
                    }
                }
                .clipShape(Capsule())
        }
        .frame(height: height)
        .shadow(color: Theme.accent.opacity(0.45), radius: 8)
        .onAppear { sweep = true }
    }
}
