//
//  FirestoreWatchlistBackend.swift
//  SceneBox
//
//  Created by SpontaneousArray on 08.08.26.
//

import Foundation
import FirebaseFirestore

struct FirestoreWatchlistBackend: WatchlistBackend {
    let uid: String
    let profileID: String

    private var collection: CollectionReference {
        Firestore.firestore()
            .collection("users").document(uid)
            .collection("profiles").document(profileID)
            .collection("watchlist")
    }

    func load() async -> [WatchlistItem] {
        guard let snapshot = try? await collection.getDocuments() else { return [] }
        return snapshot.documents.compactMap { try? $0.data(as: WatchlistItem.self) }
    }

    func upsert(_ item: WatchlistItem) async {
        try? collection.document(item.id).setData(from: item, merge: true)
    }

    func remove(id: String) async {
        try? await collection.document(id).delete()
    }
}
