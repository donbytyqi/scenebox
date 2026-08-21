//
//  OriginalAudio.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation
import SwiftVLC

nonisolated enum OriginalAudio {
    private static let bibliographic: [String: String] = [
        "deu": "ger", "fra": "fre", "zho": "chi", "nld": "dut", "ell": "gre",
        "ces": "cze", "fas": "per", "ron": "rum", "msa": "may", "sqi": "alb",
        "hye": "arm", "isl": "ice", "kat": "geo", "mkd": "mac", "slk": "slo",
        "cym": "wel", "eus": "baq", "mya": "bur", "bod": "tib",
    ]

    static func matches(_ track: Track, language code: String) -> Bool {
        let codes = candidateCodes(for: code)
        if let raw = track.language?.lowercased() {
            let base = raw.split(separator: "-").first.map(String.init) ?? raw
            if codes.contains(base) { return true }
        }
        if let name = englishName(for: code)?.lowercased() {
            if track.name.lowercased().contains(name) { return true }
            if (track.trackDescription ?? "").lowercased().contains(name) { return true }
        }
        return false
    }

    private static func candidateCodes(for code: String) -> Set<String> {
        var codes: Set<String> = [code.lowercased()]
        if let alpha3 = Locale.LanguageCode(code).identifier(.alpha3)?.lowercased() {
            codes.insert(alpha3)
            if let biblio = bibliographic[alpha3] { codes.insert(biblio) }
        }
        return codes
    }

    private static func englishName(for code: String) -> String? {
        Locale(identifier: "en_US").localizedString(forLanguageCode: code)
    }
}
