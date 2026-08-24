//
//  TraktConnectSheet.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

#if os(tvOS)
import SwiftUI

struct TraktConnectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var trakt = TraktStore.shared
    @Environment(AppSettings.self) private var settings

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "list.and.film")
                .font(.system(size: 44))
                .foregroundStyle(Theme.accent)

            Text("Connect Trakt")
                .font(.title2.weight(.bold))

            if let error = trakt.authError {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Try again") { trakt.beginDeviceAuth() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.onAccent)
            } else if let code = trakt.pendingCode {
                VStack(spacing: 8) {
                    Text("On your phone or computer, go to")
                        .foregroundStyle(.secondary)
                    Text(verificationLabel(code.verificationURL))
                        .font(.headline)
                    Text(code.userCode)
                        .font(.system(size: 42, weight: .bold, design: .monospaced))
                        .kerning(4)
                        .padding(.vertical, 8)
                }
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Waiting for approval…")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
            } else {
                ProgressView("Requesting code…")
            }

            Button("Cancel") {
                trakt.cancelDeviceAuth()
                dismiss()
            }
            .buttonStyle(.bordered)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear { trakt.beginDeviceAuth() }
        .onChange(of: settings.traktConnected) { _, connected in
            if connected { dismiss() }
        }
        .onDisappear {
            if !settings.traktConnected { trakt.cancelDeviceAuth() }
        }
    }

    private func verificationLabel(_ url: String) -> String {
        url.replacingOccurrences(of: "https://", with: "")
    }
}
#endif
