//
//  ReleaseSort.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

enum ReleaseSort: String, CaseIterable, Identifiable, Sendable {
    case quality, seeders, size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .quality: "Quality"
        case .seeders: "Seeders"
        case .size: "Size"
        }
    }

    var torrentioValue: String {
        switch self {
        case .quality: "qualitysize"
        case .seeders: "seeders"
        case .size: "size"
        }
    }
}
