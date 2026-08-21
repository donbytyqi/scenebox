//
//  ProfileEditorView.swift
//  SceneBox
//
//  Created by SpontaneousArray on 21.08.26.
//

import SwiftUI
#if canImport(PhotosUI) && !os(tvOS)
import PhotosUI
#endif

struct ProfileEditorView: View {
    enum Mode: Identifiable, Hashable {
        case create(first: Bool)
        case edit(Profile)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let p): return p.id
            }
        }
    }

    let mode: Mode
    @Environment(ProfileStore.self) private var profiles
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var colorIndex = Int.random(in: 0..<Profile.colors.count)
    @State private var pickedImage: UIImage?
    @State private var removePhoto = false
    @State private var confirmDelete = false
    @State private var saving = false
    #if canImport(PhotosUI) && !os(tvOS)
    @State private var pickerItem: PhotosPickerItem?
    #endif

    private var existing: Profile? {
        if case .edit(let p) = mode { return p }
        return nil
    }
    private var isFirst: Bool {
        if case .create(let first) = mode { return first }
        return false
    }
    private var draft: Profile {
        Profile(id: existing?.id ?? "draft",
                name: name.isEmpty ? "?" : name,
                colorIndex: colorIndex,
                avatarURLString: removePhoto ? nil : existing?.avatarURLString,
                createdAt: existing?.createdAt ?? Date())
    }
    private var canSave: Bool {
        !saving && !profiles.isWorking && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    #if os(tvOS)
    private let avatarSize: CGFloat = 220
    #else
    private let avatarSize: CGFloat = 132
    #endif

    var body: some View {
        Group {
            if isFirst {
                content
            } else {
                NavigationStack {
                    content
                        .toolbar {
                            #if !os(tvOS)
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { dismiss() }
                            }
                            #endif
                        }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            profiles.errorMessage = nil
            if let existing {
                name = existing.name
                colorIndex = existing.colorIndex
            }
        }
        .confirmationDialog("Delete this profile?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete profile", role: .destructive) {
                guard let existing else { return }
                Task {
                    await profiles.delete(existing)
                    dismiss()
                }
            }
        } message: {
            Text("Its watch history and watchlist will be removed. This can't be undone.")
        }
    }

    private var content: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 8) {
                        Text(isFirst ? "Create your profile" : (existing == nil ? "Add profile" : "Edit profile"))
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.white)
                        if isFirst {
                            Text("Everyone gets their own watch history and list.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 32)

                    ProfileAvatar(profile: draft, size: avatarSize, preview: pickedImage)

                    photoControls

                    TextField("Name", text: $name)
                        .textContentType(.name)
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                        .autocorrectionDisabled()
                        .multilineTextAlignment(.center)
                        .font(.title3)
                        .foregroundStyle(.white)
                        .tint(.white)
                        .padding()
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onChange(of: name) { _, new in
                            if new.count > Profile.maxNameLength { name = String(new.prefix(Profile.maxNameLength)) }
                        }
                        .onSubmit(save)

                    colorSwatches

                    Button(action: save) {
                        ZStack {
                            if saving || profiles.isWorking {
                                ProgressView().tint(Theme.onAccent)
                            } else {
                                Text(existing == nil ? "Create" : "Save").fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .foregroundStyle(Theme.onAccent)
                    .disabled(!canSave)

                    if existing != nil {
                        Button("Delete profile", role: .destructive) { confirmDelete = true }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(profiles.isWorking)
                    }

                    if let error = profiles.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }

    @ViewBuilder
    private var photoControls: some View {
        #if canImport(PhotosUI) && !os(tvOS)
        HStack(spacing: 16) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(draft.hasPhoto || pickedImage != nil ? "Change photo" : "Choose photo", systemImage: "photo")
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pickedImage = image
                        removePhoto = false
                    }
                }
            }
            if draft.hasPhoto || pickedImage != nil {
                Button("Remove") {
                    pickedImage = nil
                    pickerItem = nil
                    removePhoto = true
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
        }
        #else
        Text("Add a photo from the iPhone, iPad or Mac app.")
            .font(.footnote)
            .foregroundStyle(.secondary)
        #endif
    }

    private var colorSwatches: some View {
        HStack(spacing: 18) {
            ForEach(Profile.colors.indices, id: \.self) { i in
                Button {
                    colorIndex = i
                } label: {
                    Circle()
                        .fill(Profile.colors[i])
                        .frame(width: 40, height: 40)
                        .overlay {
                            if colorIndex == i {
                                Circle().strokeBorder(.white, lineWidth: 3).padding(-5)
                            }
                        }
                }
                .buttonStyle(ProfileTileStyle())
                .accessibilityLabel("Colour \(i + 1)")
            }
        }
    }

    private func save() {
        guard canSave else { return }
        saving = true
        Task {
            defer { saving = false }
            var target: Profile?
            if let existing {
                var updated = existing
                updated.name = name
                updated.colorIndex = colorIndex
                if updated.name != existing.name { await profiles.rename(existing, to: name) }
                if colorIndex != existing.colorIndex { await profiles.setColor(existing, index: colorIndex) }
                target = profiles.profiles.first { $0.id == existing.id } ?? updated
                if removePhoto, existing.hasPhoto, let t = target { await profiles.removePhoto(t) }
            } else {
                target = await profiles.create(name: name, colorIndex: colorIndex)
            }
            guard let target else { return }
            if let pickedImage {
                await profiles.setPhoto(profiles.profiles.first { $0.id == target.id } ?? target, image: pickedImage)
            }
            if profiles.errorMessage == nil {
                if isFirst { profiles.select(profiles.profiles.first { $0.id == target.id } ?? target) }
                dismiss()
            }
        }
    }
}
