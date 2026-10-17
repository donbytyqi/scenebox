//
//  FirebaseSetupView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 11.10.26.
//

import Foundation
import SwiftUI
#if !os(tvOS)
import UniformTypeIdentifiers
#endif

/// The "bring your own Firebase project" guide.
///
/// Shown instead of the sign-in form when no plist is configured, and from
/// Settings when one is.
struct FirebaseSetupView: View {
    var isSheet = false

    @Environment(\.dismiss) private var dismiss
    @State private var config = FirebaseConfigStore.shared
    @State private var isImporting = false

    private var bundleID: String {
        Bundle.main.bundleIdentifier ?? "app.scenebox.SceneBox"
    }

    var body: some View {
        Form {
            introduction
            steps
            importSection

            if config.needsRelaunch {
                relaunchSection
            }
        }
        .hideScrollBackground()
        .background(Theme.background)
        .navigationTitle("Firebase project")
        .tint(.white)
        .preferredColorScheme(.dark)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: $isImporting,
            // `.data` as well as `.propertyList`: some downloads land with a
            // generic type, and a picker that greys the file out is impossible
            // to complete.
            allowedContentTypes: [.propertyList, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                config.importConfig(from: url)
            case .failure(let error):
                config.reportPickerFailure(error)
            }
        }
        #endif
    }

    // MARK: - Sections

    private var introduction: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent)

                Text("Connect your Firebase project")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)

                Text("SceneBox has no shared server. Accounts, profiles and sync across devices run on a Firebase project that you own. Guest mode works without one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    private var steps: some View {
        Section {
            stepRow(1, "Create a project at console.firebase.google.com.")

            #if !os(tvOS)
            Link("Open the Firebase console",
                 destination: URL(string: "https://console.firebase.google.com/")!)
                .font(.footnote)
            #endif

            stepRow(2, "Add an iOS app with the bundle ID \(bundleID) and download its GoogleService-Info.plist.")

            stepRow(3, "Turn on Email/Password under Authentication → Sign-in method, and enable Firestore and Storage.")
        } header: {
            Text("Setup")
        } footer: {
            Text("The bundle ID has to match exactly, or Firebase will reject sign-in.")
        }
    }

    @ViewBuilder
    private var importSection: some View {
        Section {
            if config.hasImportedConfig {
                LabeledContent("Configuration", value: "Imported")
            } else if config.source == .bundled {
                LabeledContent("Configuration", value: "Bundled")
            }

            #if os(tvOS)
            Text("Import the plist on iPhone, iPad or Mac, then launch SceneBox on Apple TV with it already in place.")
                .font(.callout)
                .foregroundStyle(.secondary)
            #else
            Button {
                config.clearImportError()
                isImporting = true
            } label: {
                Label("Import GoogleService-Info.plist", systemImage: "doc.badge.plus")
            }

            if let error = config.importError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if config.hasImportedConfig {
                Button("Remove imported plist", role: .destructive) {
                    config.removeImportedConfig()
                }
            }
            #endif
        } header: {
            Text("Import")
        } footer: {
            if config.importError == nil && !config.hasImportedConfig {
                Text("Pick the GoogleService-Info.plist you downloaded for your iOS app in the Firebase console.")
            }
        }
    }

    private var relaunchSection: some View {
        Section {
            Label("Quit and reopen SceneBox to switch to the new Firebase project.",
                  systemImage: "arrow.clockwise")
                .foregroundStyle(.secondary)

            #if targetEnvironment(macCatalyst)
            Button("Quit SceneBox") {
                exit(0)
            }
            #endif
        } header: {
            Text("Relaunch needed")
        } footer: {
            Text("Firebase reads its configuration once, at launch, so the change applies the next time the app starts.")
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.footnote.weight(.bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 22, height: 22)
                .background(Theme.accent, in: Circle())

            Text(text)
                .foregroundStyle(.white)
        }
        .padding(.vertical, 2)
    }
}
