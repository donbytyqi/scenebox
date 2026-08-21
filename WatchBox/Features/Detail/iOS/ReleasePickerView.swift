//
//  ReleasePickerView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import SwiftUI

struct ReleasePickerView: View {
    let model: MediaDetailModel
    let request: MediaDetailModel.ReleaseRequest
    let onSelect: (TorrentStream) -> Void

    @Environment(DownloadStore.self) private var downloads
    @Environment(\.dismiss) private var dismiss

    private var navigationTitle: String {
        let action = request.intent == .watch ? "Watch" : "Download"
        if let episode = request.episode {
            return "\(action) · \(episode.label)"
        }
        return "\(action) · Sources"
    }

    #if os(tvOS)
    private var rowSpacing: CGFloat { 10 }
    private var rowEdge: CGFloat { 48 }
    #else
    private var rowSpacing: CGFloat { 8 }
    private var rowEdge: CGFloat { 16 }
    #endif

    var body: some View {
        NavigationStack {
            Group {
                if model.isLoadingReleases {
                    ProgressView("Finding sources…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = model.releaseError {
                    EmptyStateView(systemImage: "magnifyingglass",
                                   title: "No sources", message: error)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: rowSpacing) {
                            ForEach(model.releases) { stream in
                                Button { onSelect(stream) } label: {
                                    ReleaseRow(
                                        stream: stream,
                                        isDownloaded: downloads.contains(infoHash: stream.id))
                                        #if os(iOS)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 4)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Theme.surface,
                                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                        #endif
                                        .contentShape(Rectangle())
                                }
                                #if os(tvOS)
                                .buttonStyle(TVListRowButtonStyle())
                                #else
                                .buttonStyle(.plain)
                                #endif
                            }
                        }
                        .padding(.horizontal, rowEdge)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle(navigationTitle)
            .inlineNavigationBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        .preferredColorScheme(.dark)
    }
}

private struct ReleaseRow: View {
    let stream: TorrentStream
    let isDownloaded: Bool
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(stream.displayName)
                    #if os(tvOS)
                    .font(.title3.weight(.semibold))
                    #else
                    .font(.subheadline.weight(.semibold))
                    #endif
                    .lineLimit(2)
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            FlowLayout(spacing: 8) {
                if stream.isDebrid {
                    Chip(text: "Debrid", systemImage: "bolt.fill", tint: .green)
                }
                if let resolution = stream.resolution {
                    Chip(text: resolution.uppercased())
                }
                if let size = stream.sizeText {
                    Chip(text: size)
                }
                if let seeders = stream.seeders {
                    Chip(text: "\(seeders)", systemImage: "person.2.fill",
                         tint: seeders > 20 ? .green : .orange)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
        .foregroundStyle(isFocused ? .black : .white)
    }
}
