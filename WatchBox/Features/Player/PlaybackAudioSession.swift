//
//  PlaybackAudioSession.swift
//  SceneBox
//
//  Created by SpontaneousArray on 02.08.26.
//

import AVFoundation

enum PlaybackAudioSession {
    private static let queue = DispatchQueue(label: "playback.audiosession")

    static func activate() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            queue.async {
                let session = AVAudioSession.sharedInstance()
                try? session.setCategory(.playback, mode: .moviePlayback)
                try? session.setActive(true)
                done.resume()
            }
        }
    }

    static func deactivate() {
        queue.async {
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}
