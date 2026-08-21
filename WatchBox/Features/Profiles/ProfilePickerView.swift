//
//  ProfilePickerView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 21.08.26.
//

import SwiftUI

struct ProfilePickerView: View {
    @Environment(ProfileStore.self) private var profiles
    @Environment(AuthStore.self) private var auth
    @State private var editing: ProfileEditorView.Mode?
    @State private var confirmSignOut = false

    #if os(tvOS)
    private let tile: CGFloat = 200
    private let spacing: CGFloat = 48
    #else
    private let tile: CGFloat = 104
    private let spacing: CGFloat = 24
    #endif

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if !profiles.hasLoaded {
                ProgressView().tint(.white).controlSize(.large)
            } else if profiles.profiles.isEmpty {
                ProfileEditorView(mode: .create(first: true))
            } else {
                picker
            }
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editing) { mode in
            ProfileEditorView(mode: mode)
                .environment(profiles)
        }
        .alert("Sign out?", isPresented: $confirmSignOut) {
            Button("Sign out", role: .destructive) { auth.signOut() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var picker: some View {
        VStack(spacing: spacing) {
            Spacer()
            Text("Who's watching?")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)

            let columns = [GridItem(.adaptive(minimum: tile, maximum: tile), spacing: spacing)]
            LazyVGrid(columns: columns, alignment: .center, spacing: spacing) {
                ForEach(profiles.profiles) { profile in
                    ProfileTile(profile: profile, size: tile) {
                        profiles.select(profile)
                    }
                }
                if profiles.profiles.count < Profile.maxPerAccount {
                    AddProfileTile(size: tile) { editing = .create(first: false) }
                }
            }
            .frame(maxWidth: CGFloat(min(profiles.profiles.count + 1, 3)) * (tile + spacing) + spacing)

            Spacer()
            Button("Sign out") { confirmSignOut = true }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
                .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
    }
}

struct ProfileTile: View {
    let profile: Profile
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ProfileAvatar(profile: profile, size: size)
                Text(profile.name)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .frame(width: size + 16)
        }
        .buttonStyle(ProfileTileStyle())
    }
}

struct AddProfileTile: View {
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: size * 0.36, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: size, height: size)
                    .background(Color.white.opacity(0.12), in: Circle())
                Text("Add profile")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.white)
            }
            .frame(width: size + 16)
        }
        .buttonStyle(ProfileTileStyle())
    }
}

struct ProfileTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Content(configuration: configuration)
    }

    struct Content: View {
        let configuration: Configuration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .scaleEffect(isFocused ? 1.12 : (configuration.isPressed ? 0.96 : 1))
                .opacity(configuration.isPressed ? 0.8 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
