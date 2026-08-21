//
//  MediaNavigation.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import SwiftUI

struct CatalogDestination: Hashable {
    let type: MediaType
    let feed: CatalogFeed
}

extension View {
    func mediaNavigationDestinations() -> some View {
        self
            .navigationDestination(for: MediaResult.self) { item in
                MediaDetailView(mediaID: item.id, type: item.type, fallbackTitle: item.name)
                    .id(item.id)
            }
            .navigationDestination(for: CastMember.self) { member in
                ActorView(member: member)
            }
            .navigationDestination(for: PersonCredit.self) { credit in
                ResolvingDetailView(credit: credit)
            }
    }
}
