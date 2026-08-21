//
//  LibtorrentSupport.swift
//  SceneBox
//
//  Created by SpontaneousArray on 06.08.26.
//

import Foundation
import OSLog

nonisolated let torrentLog = Logger(subsystem: "TorrentKit", category: "stream")

extension TorrentEngine: @retroactive @unchecked Sendable {}

extension TKSwarmDiag: @retroactive @unchecked Sendable {}

enum TorrentEngineError: Error {
    case failedToStart
    case metadataTimeout
    case noPlayableFile
    case bufferTimeout
}

private final class OneShotData: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuation: CheckedContinuation<Data?, Never>?
    init(_ continuation: CheckedContinuation<Data?, Never>) { self.continuation = continuation }
    nonisolated func fulfill(_ data: Data?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: data)
    }
}

extension TorrentEngine {
    func resumeData() async -> Data? {
        await withCheckedContinuation { continuation in
            let once = OneShotData(continuation)
            saveResumeData(completionHandler: { once.fulfill($0) })
            DispatchQueue.global().asyncAfter(deadline: .now() + 6) { once.fulfill(nil) }
        }
    }
}

nonisolated final class PieceWaiterRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    func wait(_ index: Int, hasPiece: @Sendable (Int) -> Bool) async {
        if hasPiece(index) { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if hasPiece(index) {
                lock.unlock()
                continuation.resume()
                return
            }
            waiters[index, default: []].append(continuation)
            lock.unlock()
        }
    }

    func fulfill(_ index: Int) {
        lock.lock()
        let continuations = waiters.removeValue(forKey: index)
        lock.unlock()
        continuations?.forEach { $0.resume() }
    }

    func fulfillAll() {
        lock.lock()
        let all = waiters
        waiters.removeAll()
        lock.unlock()
        all.values.forEach { $0.forEach { $0.resume() } }
    }
}
