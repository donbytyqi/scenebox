//
//  TorrentError.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

nonisolated public enum TorrentError: Error, LocalizedError {
    case invalidMetadata(String)
    case trackerFailed(String)
    case handshakeFailed
    case pieceHashMismatch(Int)
    case storageError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidMetadata(let s): return "Invalid torrent metadata: \(s)"
        case .trackerFailed(let s): return "Tracker error: \(s)"
        case .handshakeFailed: return "Peer handshake failed"
        case .pieceHashMismatch(let i): return "Piece \(i) failed hash check"
        case .storageError(let s): return "Storage: \(s)"
        }
    }
}
