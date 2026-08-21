//
//  DeepLinkRouter.swift
//  SceneBox
//
//  Created by SpontaneousArray on 16.08.26.
//

import Foundation
import Observation

@MainActor
@Observable
final class DeepLinkRouter {
    static let shared = DeepLinkRouter()

    var pendingDetail: MediaResult?
    var pendingMagnet: MagnetLink?

    private init() {}

    @discardableResult
    func handle(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "magnet" {
            guard let magnet = MagnetLink(string: url.absoluteString) else { return false }
            pendingMagnet = magnet
            return true
        }
        guard url.scheme?.lowercased() == "scenebox" else { return false }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        var parts = url.pathComponents.filter { $0 != "/" }
        if let host = url.host, !host.isEmpty { parts.insert(host, at: 0) }
        let query = { (name: String) -> String? in
            components?.queryItems?.first { $0.name == name }?.value
        }

        switch parts.first?.lowercased() {
        case "detail" where parts.count >= 3:
            let type = MediaType(rawValue: parts[1].lowercased()) ?? .movie
            let id = parts[2]
            guard !id.isEmpty else { return false }
            pendingDetail = MediaResult(id: id, type: type, name: query("name") ?? "",
                                        year: nil, posterURL: nil, description: nil)
            return true
        case "play":
            guard let raw = query("magnet"), let magnet = MagnetLink(string: raw) else { return false }
            pendingMagnet = magnet
            return true
        default:
            return false
        }
    }
}
