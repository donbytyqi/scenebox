//
//  DebridProvider.swift
//  SceneBox
//
//  Created by SpontaneousArray on 05.08.26.
//

import Foundation

enum DebridProvider: String, CaseIterable, Identifiable, Sendable {
    case none
    case realDebrid
    case premiumize
    case allDebrid
    case torBox
    case debridLink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None (peer-to-peer)"
        case .realDebrid: "Real-Debrid"
        case .premiumize: "Premiumize"
        case .allDebrid: "AllDebrid"
        case .torBox: "TorBox"
        case .debridLink: "DebridLink"
        }
    }

    var torrentioKey: String? {
        switch self {
        case .none: nil
        case .realDebrid: "realdebrid"
        case .premiumize: "premiumize"
        case .allDebrid: "alldebrid"
        case .torBox: "torbox"
        case .debridLink: "debridlink"
        }
    }

    var cometService: String? {
        switch self {
        case .none: nil
        case .realDebrid: "realdebrid"
        case .premiumize: "premiumize"
        case .allDebrid: "alldebrid"
        case .torBox: "torbox"
        case .debridLink: "debridlink"
        }
    }

    var stremthruCode: String? {
        switch self {
        case .none: nil
        case .realDebrid: "rd"
        case .premiumize: "pm"
        case .allDebrid: "ad"
        case .torBox: "tb"
        case .debridLink: "dl"
        }
    }

    var keyHint: String? {
        switch self {
        case .none: nil
        case .realDebrid: "real-debrid.com → My Account → API token"
        case .premiumize: "premiumize.me → Account → API"
        case .allDebrid: "alldebrid.com → API keys"
        case .torBox: "torbox.app → Settings → API"
        case .debridLink: "debrid-link.com → API"
        }
    }

    var requiresKey: Bool { self != .none }
}
