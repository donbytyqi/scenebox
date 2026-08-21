//
//  PlayerPauseReassert.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import Foundation
import SwiftVLC

extension Player {
    @MainActor
    func togglePlaybackReasserting() {
        let wasActive = isPlaying
        togglePlayPause()
        guard wasActive else { return }   // we intended to pause
        Task { @MainActor [weak self] in
            for _ in 0..<8 {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self else { return }
                if self.state == .paused || self.isPlaying { return }
                self.pause()
            }
        }
    }
}
