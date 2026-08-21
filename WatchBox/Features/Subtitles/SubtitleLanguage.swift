//
//  SubtitleLanguage.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

nonisolated struct SubtitleLanguage: Identifiable, Sendable, Hashable {
    let code: String   // "eng", "spa", … ; "" means "off / none"
    let name: String

    var id: String { code }

    static let common: [SubtitleLanguage] = [
        .init(code: "", name: "Off"),
        .init(code: "eng", name: "English"),
        .init(code: "spa", name: "Spanish"),
        .init(code: "fre", name: "French"),
        .init(code: "ger", name: "German"),
        .init(code: "ita", name: "Italian"),
        .init(code: "por", name: "Portuguese"),
        .init(code: "pob", name: "Portuguese (BR)"),
        .init(code: "dut", name: "Dutch"),
        .init(code: "rus", name: "Russian"),
        .init(code: "ara", name: "Arabic"),
        .init(code: "tur", name: "Turkish"),
        .init(code: "pol", name: "Polish"),
        .init(code: "swe", name: "Swedish"),
        .init(code: "jpn", name: "Japanese"),
        .init(code: "kor", name: "Korean"),
        .init(code: "chi", name: "Chinese"),
    ]

    static var offered: [SubtitleLanguage] {
        let device = deviceDefault
        return common.contains(device) ? common : common + [device]
    }

    static var deviceDefault: SubtitleLanguage {
        let iso639_1 = Locale.current.language.languageCode?.identifier ?? "en"
        if iso639_1 == "pt", Locale.current.region?.identifier == "BR",
           let br = common.first(where: { $0.code == "pob" }) {
            return br
        }
        if iso639_1 == "zh", Locale.current.language.script?.identifier == "Hant" {
            return .init(code: "zht", name: "Chinese (Traditional)")
        }
        let code = iso639_1ToOpenSubtitles[iso639_1] ?? "eng"
        return common.first(where: { $0.code == code })
            ?? .init(code: code, name: displayName(for: code))
    }

    private static let iso639_1ToOpenSubtitles: [String: String] = [
        "en": "eng", "es": "spa", "fr": "fre", "de": "ger", "it": "ita",
        "pt": "por", "nl": "dut", "ru": "rus", "ar": "ara", "tr": "tur",
        "pl": "pol", "sv": "swe", "ja": "jpn", "ko": "kor", "zh": "chi",
        "cs": "cze", "da": "dan", "el": "ell", "fi": "fin", "he": "heb",
        "hi": "hin", "hr": "hrv", "hu": "hun", "id": "ind", "nb": "nor",
        "no": "nor", "nn": "nor", "fa": "per", "ro": "rum", "sl": "slv",
        "sr": "srp", "th": "tha", "uk": "ukr", "vi": "vie", "ms": "may",
        "bg": "bul", "et": "est", "sq": "alb",
    ]

    static func displayName(for code: String) -> String {
        if let match = all[code] { return match }
        return code.uppercased()
    }

    private static let all: [String: String] = {
        var map = Dictionary(uniqueKeysWithValues: common.map { ($0.code, $0.name) })
        map["cze"] = "Czech"; map["dan"] = "Danish"; map["ell"] = "Greek"
        map["fin"] = "Finnish"; map["heb"] = "Hebrew"; map["hin"] = "Hindi"
        map["hrv"] = "Croatian"; map["hun"] = "Hungarian"; map["ind"] = "Indonesian"
        map["nor"] = "Norwegian"; map["per"] = "Persian"; map["rum"] = "Romanian"
        map["ron"] = "Romanian"; map["slv"] = "Slovenian"; map["srp"] = "Serbian"
        map["tha"] = "Thai"; map["ukr"] = "Ukrainian"; map["vie"] = "Vietnamese"
        map["zht"] = "Chinese (Traditional)"; map["zhe"] = "Chinese (Simplified)"
        map["may"] = "Malay"; map["bul"] = "Bulgarian"; map["est"] = "Estonian"
        map["alb"] = "Albanian"
        return map
    }()
}
