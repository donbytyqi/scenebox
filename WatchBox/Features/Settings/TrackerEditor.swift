//
//  TrackerEditor.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import SwiftUI

struct TrackerEditor: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            PageTitleRow("Custom trackers")
            Section {
                #if os(tvOS)
                TextField("Tracker URLs", text: $settings.customTrackers)
                    .font(.caption.monospaced())
                    .tint(.white)
                #else
                TextEditor(text: $settings.customTrackers)
                    .font(.caption.monospaced())
                    .frame(minHeight: 220)
                    .tint(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                #endif
            } footer: {
                Text("One tracker URL per line, e.g. udp://tracker.example.org:1337/announce")
            }
        }
        .hideScrollBackground()
        .background(Theme.background)
        .pageTitle("Custom trackers")
        .inlineNavigationBar()
    }
}
