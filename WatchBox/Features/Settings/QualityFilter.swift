//
//  QualityFilter.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

enum QualityFilter: String, CaseIterable, Identifiable, Sendable {
    case brremux, hdrall = "hdrall", dolbyvision = "dolbyvision"
    case threeD = "threed"
    case unknown, scr, cam, other
    case sd = "480p"
    case hd720 = "720p"
    case hd1080 = "1080p"
    case uhd = "4k"

    var id: String { rawValue }

    static var offered: [QualityFilter] { [.cam, .scr, .unknown, .sd, .hd720, .hd1080, .uhd] }

    var title: String {
        switch self {
        case .cam: "CAM rips"
        case .scr: "Screeners"
        case .unknown: "Unknown quality"
        case .sd: "480p"
        case .hd720: "720p"
        case .hd1080: "1080p"
        case .uhd: "4K"
        case .brremux: "BluRay remux"
        case .hdrall: "HDR"
        case .dolbyvision: "Dolby Vision"
        case .threeD: "3D"
        case .other: "Other"
        }
    }
}
