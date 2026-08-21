//
//  NetworkIO.swift
//  SceneBox
//
//  Created by SpontaneousArray on 28.07.26.
//

import Foundation
import Network

nonisolated enum NetworkIO {
    enum Failure: Error {
        case closed          // peer closed the stream cleanly
        case notReady        // connection never reached `.ready`
    }

    static func start(_ connection: NWConnection, on queue: DispatchQueue) async throws {
        let states = AsyncStream<NWConnection.State> { continuation in
            connection.stateUpdateHandler = { continuation.yield($0) }
            continuation.onTermination = { _ in connection.stateUpdateHandler = nil }
        }

        try await withTaskCancellationHandler {
            connection.start(queue: queue)
            for await state in states {
                switch state {
                case .ready:
                    return
                case .failed(let error):
                    throw error
                case .cancelled:
                    throw Failure.notReady
                default:
                    continue    // .setup / .preparing / .waiting — keep waiting
                }
            }
            throw Failure.notReady
        } onCancel: {
            connection.cancel()
        }
    }

    static func send(_ connection: NWConnection, _ data: Data) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
            }
        } onCancel: {
            connection.cancel()
        }
    }

    static func receive(_ connection: NWConnection,
                        atLeast minimum: Int = 1,
                        atMost maximum: Int) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receive(minimumIncompleteLength: minimum, maximumLength: maximum) { data, _, _, error in
                    if let error { continuation.resume(throwing: error); return }
                    if let data, !data.isEmpty { continuation.resume(returning: data); return }
                    continuation.resume(throwing: Failure.closed)
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    static func receiveMessage(_ connection: NWConnection, minimumLength: Int) async throws -> Data {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
                connection.receiveMessage { data, _, _, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let data, data.count >= minimumLength else {
                        continuation.resume(throwing: TorrentError.trackerFailed("short udp packet"))
                        return
                    }
                    continuation.resume(returning: data)
                }
            }
        } onCancel: {
            connection.cancel()
        }
    }

    static func withTimeout<T: Sendable>(_ duration: Duration,
                                         throwing timeoutError: @autoclosure @escaping @Sendable () -> Error,
                                         operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw timeoutError()
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
