//
//  ProfileStore.swift
//  SceneBox
//
//  Created by SpontaneousArray on 21.08.26.
//

import Foundation
import Observation
import FirebaseFirestore
import FirebaseStorage
import UIKit

@MainActor
@Observable
final class ProfileStore {
    static let shared = ProfileStore()

    private(set) var profiles: [Profile] = []
    private(set) var selected: Profile?
    private(set) var hasLoaded = false
    private(set) var isWorking = false
    var errorMessage: String?

    @ObservationIgnored private var uid: String?
    @ObservationIgnored private var listener: ListenerRegistration?

    private var collection: CollectionReference? {
        uid.map { Firestore.firestore().collection("users").document($0).collection("profiles") }
    }

    // MARK: Lifecycle

    func activate(uid: String) {
        guard self.uid != uid else { return }
        deactivate()
        self.uid = uid
        guard let collection else { return }
        listener = collection.addSnapshotListener { [weak self] snapshot, _ in
            let loaded = snapshot?.documents.compactMap { try? $0.data(as: Profile.self) } ?? []
            let fromCache = snapshot?.metadata.isFromCache ?? true
            Task { @MainActor in
                guard let self else { return }
                self.profiles = loaded.sorted { $0.createdAt < $1.createdAt }
                if let current = self.selected {
                    self.selected = self.profiles.first { $0.id == current.id }
                }
                if !fromCache || !loaded.isEmpty { self.hasLoaded = true }
            }
        }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            self?.hasLoaded = true
        }
    }

    func deactivate() {
        listener?.remove()
        listener = nil
        uid = nil
        profiles = []
        selected = nil
        hasLoaded = false
    }

    func select(_ profile: Profile) { selected = profile }
    func deselect() { selected = nil }

    // MARK: Mutations

    @discardableResult
    func create(name: String, colorIndex: Int? = nil) async -> Profile? {
        guard let uid, let collection, profiles.count < Profile.maxPerAccount else { return nil }
        let trimmed = Self.clean(name)
        guard !trimmed.isEmpty else { return nil }
        let profile = Profile(id: UUID().uuidString, name: trimmed,
                              colorIndex: colorIndex ?? Int.random(in: 0..<Profile.colors.count),
                              avatarURLString: nil, createdAt: Date())
        isWorking = true; defer { isWorking = false }
        do {
            try collection.document(profile.id).setData(from: profile)
        } catch {
            errorMessage = "Couldn't create the profile. Please try again."
            return nil
        }
        if !profiles.contains(where: { $0.id == profile.id }) { profiles.append(profile) }
        if profiles.count == 1 {
            await LegacyProfileMigration.migrate(uid: uid, into: profile.id)
        }
        return profile
    }

    func rename(_ profile: Profile, to name: String) async {
        let trimmed = Self.clean(name)
        guard !trimmed.isEmpty, trimmed != profile.name else { return }
        var updated = profile; updated.name = trimmed
        await save(updated)
    }

    func setColor(_ profile: Profile, index: Int) async {
        var updated = profile; updated.colorIndex = index
        await save(updated)
    }

    func setPhoto(_ profile: Profile, image: UIImage) async {
        guard let uid else { return }
        isWorking = true; defer { isWorking = false }
        guard let data = Self.avatarJPEG(from: image) else {
            errorMessage = "That image couldn't be used."
            return
        }
        let ref = Storage.storage().reference(withPath: profile.avatarStoragePath(uid: uid))
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        do {
            _ = try await ref.putDataAsync(data, metadata: metadata)
            let url = try await ref.downloadURL()
            var updated = profile
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let existingItems = parts?.queryItems ?? []
            parts?.queryItems = existingItems + [URLQueryItem(name: "v", value: String(Int(Date().timeIntervalSince1970)))]
            updated.avatarURLString = (parts?.url ?? url).absoluteString
            await save(updated)
        } catch {
            errorMessage = "Couldn't upload the photo. Check your connection and try again."
        }
    }

    func removePhoto(_ profile: Profile) async {
        guard let uid else { return }
        try? await Storage.storage().reference(withPath: profile.avatarStoragePath(uid: uid)).delete()
        var updated = profile; updated.avatarURLString = nil
        await save(updated)
    }

    func delete(_ profile: Profile) async {
        guard let uid, let collection else { return }
        isWorking = true; defer { isWorking = false }
        let doc = collection.document(profile.id)
        for sub in ["watching", "watchlist"] {
            if let snap = try? await doc.collection(sub).getDocuments() {
                for d in snap.documents { try? await d.reference.delete() }
            }
        }
        try? await Storage.storage().reference(withPath: profile.avatarStoragePath(uid: uid)).delete()
        do {
            try await doc.delete()
        } catch {
            errorMessage = "Couldn't delete the profile. Please try again."
            return
        }
        profiles.removeAll { $0.id == profile.id }
        if selected?.id == profile.id { selected = nil }
    }

    // MARK: Helpers

    private func save(_ profile: Profile) async {
        guard let collection else { return }
        do {
            try collection.document(profile.id).setData(from: profile, merge: true)
        } catch {
            errorMessage = "Couldn't save the profile. Please try again."
            return
        }
        if let i = profiles.firstIndex(where: { $0.id == profile.id }) { profiles[i] = profile }
        if selected?.id == profile.id { selected = profile }
    }

    private static func clean(_ name: String) -> String {
        String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Profile.maxNameLength))
    }

    nonisolated private static func avatarJPEG(from image: UIImage) -> Data? {
        let side: CGFloat = 512
        let scale = max(side / image.size.width, side / image.size.height)
        let scaled = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let origin = CGPoint(x: (side - scaled.width) / 2, y: (side - scaled.height) / 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(origin: origin, size: scaled))
        }
        return square.jpegData(compressionQuality: 0.85)
    }
}

private enum LegacyProfileMigration {
    static func migrate(uid: String, into profileID: String) async {
        let user = Firestore.firestore().collection("users").document(uid)
        let target = user.collection("profiles").document(profileID)
        for sub in ["watching", "watchlist"] {
            guard let snap = try? await user.collection(sub).getDocuments(), !snap.isEmpty else { continue }
            for doc in snap.documents {
                try? await target.collection(sub).document(doc.documentID).setData(doc.data())
                try? await doc.reference.delete()
            }
        }
    }
}
