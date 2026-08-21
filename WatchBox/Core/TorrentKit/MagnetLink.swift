//
//  MagnetLink.swift
//  SceneBox
//
//  Created by SpontaneousArray on 28.07.26.
//

import Foundation

nonisolated public struct MagnetLink: Sendable, Equatable {
    public let infoHash: Data        // 20 bytes
    public let displayName: String?
    public let trackers: [URL]

    public init?(string: String) {
        guard string.hasPrefix("magnet:?"),
              let comps = URLComponents(string: string),
              let items = comps.queryItems else { return nil }

        var hash: Data?
        var name: String?
        var trackers: [URL] = []

        for item in items {
            switch item.name {
            case "xt":
                guard let value = item.value, value.lowercased().hasPrefix("urn:btih:") else { continue }
                let id = String(value.dropFirst("urn:btih:".count))
                hash = MagnetLink.decodeInfoHash(id)
            case "dn":
                name = item.value?.removingPercentEncoding
            case "tr":
                if let v = item.value?.removingPercentEncoding, let u = URL(string: v) { trackers.append(u) }
            default:
                break
            }
        }
        guard let h = hash else { return nil }
        self.infoHash = h
        self.displayName = name
        self.trackers = trackers
    }

    public init(infoHash: Data, displayName: String? = nil, trackers: [URL] = []) {
        self.infoHash = infoHash; self.displayName = displayName; self.trackers = trackers
    }

    static func decodeInfoHash(_ s: String) -> Data? {
        if s.count == 40, let d = Data(hex: s) { return d }
        if s.count == 32, let d = Data(base32: s.uppercased()) { return d }
        return nil
    }

    public var magnetURI: String {
        var uri = "magnet:?xt=urn:btih:\(infoHash.hexString)"
        if let displayName, let enc = displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            uri += "&dn=\(enc)"
        }
        for t in trackers {
            guard let enc = t.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { continue }
            uri += "&tr=\(enc)"
        }
        return uri
    }
}

nonisolated extension Data {
    init?(hex: String) {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var out = Data(capacity: chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i...i+1]), radix: 16) else { return nil }
            out.append(byte)
        }
        self = out
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined() }

    init?(base32: String) {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
        var lookup = [Character: UInt8]()
        for (i, c) in alphabet.enumerated() { lookup[c] = UInt8(i) }
        var bits = 0, value = 0
        var out = Data()
        for c in base32 where c != "=" {
            guard let v = lookup[c] else { return nil }
            value = (value << 5) | Int(v); bits += 5
            if bits >= 8 { out.append(UInt8((value >> (bits - 8)) & 0xFF)); bits -= 8 }
        }
        self = out
    }
}
