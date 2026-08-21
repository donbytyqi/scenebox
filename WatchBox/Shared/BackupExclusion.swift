//
//  BackupExclusion.swift
//  SceneBox
//
//  Created by SpontaneousArray on 16.08.26.
//

import Foundation

nonisolated enum BackupExclusion {
    static func exclude(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }
}
