//
//  ByteFormat.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

enum ByteFormat {
    static func size(_ bytes: Int64) -> String {
        guard bytes > 0 else { return "0 KB" }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        guard bytesPerSecond > 0 else { return "0 KB/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .file) + "/s"
    }

    static func percent(_ fraction: Double) -> String {
        String(format: "%.0f%%", min(max(fraction, 0), 1) * 100)
    }

    static func percentDetailed(_ fraction: Double) -> String {
        let pct = min(max(fraction, 0), 1) * 100
        if pct > 0, pct < 10 { return String(format: "%.2f%%", pct) }
        return String(format: "%.1f%%", pct)
    }

    static func bytes(fromSizeText text: String) -> Int64? {
        let parts = text.split(separator: " ")
        guard let value = Double(parts.first ?? "") else { return nil }
        let unit = (parts.count > 1 ? parts[1] : "").uppercased()
        let multiplier: Double
        switch unit {
        case "TB", "TIB": multiplier = 1_000_000_000_000
        case "GB", "GIB": multiplier = 1_000_000_000
        case "MB", "MIB": multiplier = 1_000_000
        case "KB", "KIB": multiplier = 1_000
        default: return nil
        }
        return Int64(value * multiplier)
    }
}
