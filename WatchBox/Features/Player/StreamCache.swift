//
//  StreamCache.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import Foundation

nonisolated enum StreamCache {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Streams", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            BackupExclusion.exclude(url)
        }
        return url
    }

    static func removeLegacyLocation() {
        let legacy = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Streams", isDirectory: true)
        try? FileManager.default.removeItem(at: legacy)
    }

    private static func scan(_ directory: URL) -> (size: Int64, modified: Date) {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .contentModificationDateKey, .isRegularFileKey])
        else { return (0, .distantPast) }
        var total: Int64 = 0
        var newest: Date = .distantPast
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [.totalFileAllocatedSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
            if let modified = values.contentModificationDate, modified > newest { newest = modified }
        }
        return (total, newest)
    }

    private static func entryURLs() -> [URL] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    static func totalBytes() -> Int64 {
        entryURLs().reduce(0) { $0 + scan($1).size }
    }

    static func prune(toBytes limitBytes: Int64, keeping: Set<String> = []) {
        var items = entryURLs().map { (url: $0, scan: scan($0)) }
        var total = items.reduce(0) { $0 + $1.scan.size }
        guard total > limitBytes else { return }
        items.sort { $0.scan.modified < $1.scan.modified }   // oldest first
        for item in items where total > limitBytes {
            if keeping.contains(item.url.lastPathComponent) { continue }
            try? FileManager.default.removeItem(at: item.url)
            total -= item.scan.size
        }
    }

    static func remove(infoHash: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(infoHash, isDirectory: true))
    }

    static func clear() {
        try? FileManager.default.removeItem(at: root)
    }
}
