//
//  StreamProvider.swift
//  SceneBox
//
//  Created by SpontaneousArray on 05.08.26.
//

import Foundation

public enum StreamProvider: String, CaseIterable, Identifiable, Sendable {
    case torrentio
    case comet
    case stremthru

    public var id: String { rawValue }

    static let queryOrder: [StreamProvider] = [.torrentio, .stremthru, .comet]

    var title: String {
        switch self {
        case .torrentio: "Torrentio"
        case .comet: "Comet"
        case .stremthru: "StremThru"
        }
    }

    var requiresDebrid: Bool { self == .comet }

    func baseURL(debrid: DebridProvider, key: String, torrentioConfig: String,
                 shareKeyWithCommunityHosts: Bool = false,
                 stremthruHost: String = StreamProvider.defaultStremthruHost) -> String? {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasDebrid = debrid.requiresKey && !key.isEmpty
        let communityDebrid = hasDebrid && shareKeyWithCommunityHosts

        switch self {
        case .torrentio:
            let plain = "https://torrentio.strem.fun"
            return torrentioConfig.isEmpty ? plain : "\(plain)/\(torrentioConfig)"

        case .comet:
            guard communityDebrid, let service = debrid.cometService else { return nil }
            let json: [String: Any] = ["debridService": service, "debridApiKey": key]
            guard let cfg = Self.base64JSON(json) else { return nil }
            return "https://comet.elfhosted.com/\(cfg)"

        case .stremthru:
            let store: [String: String]
            if communityDebrid, let code = debrid.stremthruCode {
                store = ["c": code, "t": key]
            } else {
                store = ["c": "p2p", "t": ""]   // key-free peer-to-peer
            }
            guard let cfg = Self.base64JSON(["stores": [store]]) else { return nil }
            var host = stremthruHost.trimmingCharacters(in: .whitespacesAndNewlines)
            while host.hasSuffix("/") { host.removeLast() }
            if host.isEmpty { host = Self.defaultStremthruHost }
            if !host.hasPrefix("http://") && !host.hasPrefix("https://") { host = "https://" + host }
            return "\(host)/stremio/torz/\(cfg)"
        }
    }

    nonisolated static let defaultStremthruHost = "https://stremthru.13377001.xyz"

    private static func base64JSON(_ object: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return data.base64EncodedString()
    }
}
