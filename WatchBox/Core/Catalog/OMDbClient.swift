//
//  OMDbClient.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation

public actor OMDbClient {
    private let key: String
    private let base = "https://www.omdbapi.com/"

    public init?(key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        self.key = trimmed
    }

    public func ratings(imdbID: String) async -> MediaRatings? {
        guard var comps = URLComponents(string: base) else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "i", value: imdbID),
            URLQueryItem(name: "apikey", value: key),
        ]
        guard let url = comps.url,
              let obj = (try? await HTTP.get(url))?.object,
              (obj["Response"] as? String) != "False" else { return nil }

        var ratings = MediaRatings()
        ratings.imdb = (obj["imdbRating"] as? String).flatMap(Double.init)
        for entry in obj["Ratings"] as? [[String: Any]] ?? [] {
            guard let source = entry["Source"] as? String,
                  let value = entry["Value"] as? String else { continue }
            switch source {
            case "Rotten Tomatoes":
                ratings.rottenTomatoes = Int(value.replacingOccurrences(of: "%", with: ""))
            case "Metacritic":
                ratings.metacritic = value.split(separator: "/").first.flatMap { Int($0) }
            default:
                break
            }
        }
        return ratings.isEmpty ? nil : ratings
    }
}
