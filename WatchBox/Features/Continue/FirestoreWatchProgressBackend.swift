//
//  FirestoreWatchProgressBackend.swift
//  SceneBox
//
//  Created by SpontaneousArray on 01.08.26.
//

import Foundation
import FirebaseFirestore

struct FirestoreWatchProgressBackend: WatchProgressBackend {
    let uid: String
    let profileID: String

    private var collection: CollectionReference {
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("profiles").document(profileID)
            .collection("watching")
    }

    func load() async -> [WatchProgress] {
        guard let snapshot = try? await collection.getDocuments() else { return [] }
        return snapshot.documents.compactMap { try? $0.data(as: WatchProgress.self) }
    }

    func upsert(_ item: WatchProgress) async {
        try? collection.document(item.id).setData(from: item, merge: true)
    }

    func remove(id: String) async {
        try? await collection.document(id).delete()
    }

    func clear() async {
        guard let snapshot = try? await collection.getDocuments() else { return }
        for document in snapshot.documents {
            try? await document.reference.delete()
        }
    }
}
