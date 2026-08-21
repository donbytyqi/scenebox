//
//  DownloadError.swift
//  SceneBox
//
//  Created by SpontaneousArray on 29.07.26.
//

import Foundation

enum DownloadError: Error, LocalizedError {
    case badMagnet
    case missingMetadata
    case storageCapReached

    var errorDescription: String? {
        switch self {
        case .badMagnet: "This release's magnet link is malformed."
        case .missingMetadata: "Downloaded file metadata is missing."
        case .storageCapReached: "Storage limit reached. Free up space or raise the limit in Settings › Storage."
        }
    }
}
