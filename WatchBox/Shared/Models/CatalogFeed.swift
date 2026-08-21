//
//  CatalogFeed.swift
//  SceneBox
//
//  Created by SpontaneousArray on 30.07.26.
//

import Foundation

nonisolated public enum CatalogFeed: String, Sendable, CaseIterable, Identifiable {
    case popular = "top"
    case new = "year"
    case featured = "imdbRating"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .popular: "Popular"
        case .new: "New"
        case .featured: "Featured"
        }
    }

    public var systemImage: String {
        switch self {
        case .popular: "flame"
        case .new: "sparkles"
        case .featured: "star"
        }
    }

    public var kitsuCatalog: String {
        switch self {
        case .popular: "kitsu-anime-popular"
        case .new: "kitsu-anime-airing"
        case .featured: "kitsu-anime-rating"
        }
    }
}
