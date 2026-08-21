//
//  DebridDownloader.swift
//  SceneBox
//
//  Created by SpontaneousArray on 31.07.26.
//

import Foundation

nonisolated final class DebridDownloader: NSObject, @unchecked Sendable {
    struct Progress: Sendable {
        let downloadedBytes: Int64
        let totalBytes: Int64
    }

    private let destination: URL
    private let onProgress: @Sendable (Progress) -> Void
    private let onComplete: @Sendable (Result<URL, Error>) -> Void

    private var session: URLSession!
    private var task: URLSessionDataTask?
    private var handle: FileHandle?
    private var sourceURL: URL?

    private let lock = NSLock()
    private var downloaded: Int64 = 0
    private var expectedTotal: Int64 = 0        // full file length, not the remaining slice
    private var lastActivity = Date()
    private var attempt = 0
    private var isDone = false
    private var isCancelled = false
    private var lastReportAt = Date.distantPast

    private var watchdog: Task<Void, Never>?

    private let stallTimeout: TimeInterval = 20
    private let maxAttempts = 12

    init(destination: URL,
         onProgress: @escaping @Sendable (Progress) -> Void,
         onComplete: @escaping @Sendable (Result<URL, Error>) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
        self.onComplete = onComplete
        super.init()
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 45   // our watchdog is the tighter net
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1   // serialise all delegate callbacks
        session = URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }

    func start(url: URL) {
        sourceURL = url
        openFileForResume()
        beginRequest()
        watchdog = Task { [weak self] in await self?.runWatchdog() }
    }

    func cancel() {
        lock.lock(); isCancelled = true; lock.unlock()
        watchdog?.cancel()
        task?.cancel()
        session.invalidateAndCancel()
    }

    // MARK: - File

    private func openFileForResume() {
        let fm = FileManager.default
        try? fm.createDirectory(at: destination.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if !fm.fileExists(atPath: destination.path) {
            fm.createFile(atPath: destination.path, contents: nil)
        }
        handle = try? FileHandle(forWritingTo: destination)
        let end = (try? handle?.seekToEnd()) ?? 0
        lock.lock(); downloaded = Int64(end); lock.unlock()
    }

    private func beginRequest() {
        guard let sourceURL else { return }
        lock.lock(); let from = downloaded; lastActivity = Date(); lock.unlock()

        var request = URLRequest(url: sourceURL)
        request.setValue("bytes=\(from)-", forHTTPHeaderField: "Range")
        let task = session.dataTask(with: request)
        self.task = task
        task.resume()
    }

    // MARK: - Watchdog

    private func runWatchdog() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(5))
            let stalled = lock.withLock {
                !isDone && !isCancelled
                    && Date().timeIntervalSince(lastActivity) > stallTimeout
            }
            if stalled { task?.cancel() }
        }
    }

    // MARK: - Completion

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        if isDone { lock.unlock(); return }
        isDone = true
        lock.unlock()
        watchdog?.cancel()
        try? handle?.synchronize()
        try? handle?.close()
        session.finishTasksAndInvalidate()
        onComplete(result)
    }

    private func scheduleResume(after error: Error?) {
        lock.lock()
        attempt += 1
        let attempts = attempt
        let cancelled = isCancelled
        lock.unlock()
        guard !cancelled else { return }
        guard attempts <= maxAttempts else {
            finish(.failure(error ?? URLError(.cannotLoadFromNetwork)))
            return
        }
        let backoff = min(Double(attempts) * 1.5, 8)
        DispatchQueue.global().asyncAfter(deadline: .now() + backoff) { [weak self] in
            guard let self else { return }
            self.lock.lock(); let stop = self.isCancelled || self.isDone; self.lock.unlock()
            guard !stop else { return }
            self.beginRequest()
        }
    }
}

extension DebridDownloader: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                                didReceive response: URLResponse,
                                completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 200

        if status == 416 {
            completionHandler(.cancel)
            finish(.success(destination))
            return
        }

        completionHandler(.allow)

        lock.lock()
        if status == 200 {
            try? handle?.seek(toOffset: 0)
            try? handle?.truncate(atOffset: 0)
            downloaded = 0
            if response.expectedContentLength > 0 { expectedTotal = response.expectedContentLength }
        } else {
            if let range = http?.value(forHTTPHeaderField: "Content-Range"),
               let total = range.split(separator: "/").last.flatMap({ Int64($0) }) {
                expectedTotal = total
            } else if response.expectedContentLength > 0 {
                expectedTotal = downloaded + response.expectedContentLength
            }
        }
        lastActivity = Date()
        lock.unlock()
    }

    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        try? handle?.write(contentsOf: data)

        lock.lock()
        downloaded += Int64(data.count)
        lastActivity = Date()
        attempt = 0                     // real progress clears the failure streak
        let d = downloaded, t = expectedTotal
        let now = Date()
        let report = now.timeIntervalSince(lastReportAt) >= 0.3
        if report { lastReportAt = now }
        lock.unlock()

        if report { onProgress(Progress(downloadedBytes: d, totalBytes: t)) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let cancelled = isCancelled
        let done = isDone
        let d = downloaded, t = expectedTotal
        lock.unlock()

        if done { return }

        if cancelled {
            try? handle?.close()
            return
        }

        if error == nil, t <= 0 || d >= t {
            onProgress(Progress(downloadedBytes: d, totalBytes: max(t, d)))
            finish(.success(destination))
            return
        }

        scheduleResume(after: error)
    }
}
