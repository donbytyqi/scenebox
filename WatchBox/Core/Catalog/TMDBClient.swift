//
//  TMDBClient.swift
//  SceneBox
//
//  Created by SpontaneousArray on 10.08.26.
//

import Foundation

public actor TMDBClient {
    private let key: String
    private let base = "https://api.themoviedb.org/3"
    private let imageBase = "https://image.tmdb.org/t/p"

    public init?(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        self.key = trimmed
    }

    public func cast(tmdbID: Int, type: MediaType) async -> [CastMember] {
        guard let obj = await get("/\(kind(type))/\(tmdbID)/credits") else { return [] }
        let cast = obj["cast"] as? [[String: Any]] ?? []
        return cast.compactMap { member in
            guard let id = member["id"] as? Int, let name = member["name"] as? String else { return nil }
            return CastMember(id: id, name: name,
                              role: member["character"] as? String,
                              photoURL: image(member["profile_path"], size: "w300"))
        }
    }

    public func filmography(personID: Int) async -> [PersonCredit] {
        guard let obj = await get("/person/\(personID)/combined_credits") else { return [] }
        let credits = obj["cast"] as? [[String: Any]] ?? []
        let sorted = credits.sorted { (($0["popularity"] as? Double) ?? 0) > (($1["popularity"] as? Double) ?? 0) }
        var seen = Set<Int>()
        var out: [PersonCredit] = []
        for credit in sorted {
            guard let id = credit["id"] as? Int, seen.insert(id).inserted else { continue }
            let media = credit["media_type"] as? String
            guard media == "movie" || media == "tv" else { continue }
            let type: MediaType = media == "tv" ? .series : .movie
            let title = (credit["title"] as? String) ?? (credit["name"] as? String) ?? "Untitled"
            let date = (credit["release_date"] as? String) ?? (credit["first_air_date"] as? String)
            let year = date.flatMap { $0.split(separator: "-").first.map(String.init) }
            out.append(PersonCredit(id: id, type: type, title: title, year: year,
                                    posterURL: image(credit["poster_path"], size: "w342")))
        }
        return out
    }

    public func originalLanguage(tmdbID: Int, type: MediaType) async -> String? {
        guard let obj = await get("/\(kind(type))/\(tmdbID)") else { return nil }
        let code = obj["original_language"] as? String
        return (code?.isEmpty == false) ? code : nil
    }

    public func imdbID(tmdbID: Int, type: MediaType) async -> String? {
        guard let obj = await get("/\(kind(type))/\(tmdbID)/external_ids") else { return nil }
        let imdb = obj["imdb_id"] as? String
        return (imdb?.isEmpty == false) ? imdb : nil
    }

    // MARK: - Plumbing

    private func kind(_ type: MediaType) -> String { type == .series ? "tv" : "movie" }

    private func image(_ path: Any?, size: String) -> URL? {
        guard let path = path as? String, !path.isEmpty else { return nil }
        return URL(string: "\(imageBase)/\(size)\(path)")
    }

    private func get(_ path: String) async -> [String: Any]? {
        guard var comps = URLComponents(string: "\(base)\(path)") else { return nil }
        comps.queryItems = (comps.queryItems ?? []) + [URLQueryItem(name: "api_key", value: key)]
        guard let url = comps.url,
              let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
