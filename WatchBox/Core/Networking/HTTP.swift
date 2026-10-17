//
//  HTTP.swift
//  SceneBox
//
//  Created by SpontaneousArray on 24.08.26.
//

import Foundation

nonisolated enum HTTP {
    struct Response: Sendable {
        let status: Int
        let data: Data

        var isSuccess: Bool { (200..<300).contains(status) }
        var object: [String: Any]? { (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] }
        var array: [[String: Any]]? { (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] }
    }

    static func get(_ url: URL, headers: [String: String] = [:],
                    timeout: TimeInterval = 20,
                    cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) async throws -> Response {
        try await send(request(url, headers: headers, timeout: timeout, cachePolicy: cachePolicy))
    }

    static func post(_ url: URL, json: [String: Any],
                     headers: [String: String] = [:],
                     timeout: TimeInterval = 20) async throws -> Response {
        var request = request(url, headers: headers, timeout: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: json)
        return try await send(request)
    }

    private static func request(_ url: URL, headers: [String: String],
                                timeout: TimeInterval,
                                cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        request.cachePolicy = cachePolicy
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        return request
    }

    private static func send(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await URLSession.shared.data(for: request)
        return Response(status: (response as? HTTPURLResponse)?.statusCode ?? 200, data: data)
    }
}
