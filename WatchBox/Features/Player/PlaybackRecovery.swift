import Foundation

/// Keeps the resume point independently of VLC, which clears its clock on stop.
struct PlaybackRecovery {
    var position: Duration = .zero
    private(set) var attempts = 0
    private var lastSample: Duration?
    private var stalledFor: Duration = .zero
    private var healthyFor: Duration = .zero

    func endedPrematurely(duration: Duration) -> Bool {
        duration > .zero && duration - position > .seconds(5)
    }

    mutating func reserveRetry(limit: Int) -> Bool {
        guard attempts < limit else { return false }
        attempts += 1
        resetObservation()
        return true
    }

    mutating func resetAttempts() {
        attempts = 0
        resetObservation()
    }

    mutating func resetObservation() {
        lastSample = nil
        stalledFor = .zero
        healthyFor = .zero
    }

    /// Pauses and recovery work must pass `expectedToAdvance: false`.
    mutating func observe(time: Duration, elapsed: Duration,
                          expectedToAdvance: Bool, timeout: Duration) -> Bool {
        // A suspended app has no samples; that gap is not evidence of a stall.
        guard expectedToAdvance, elapsed <= .seconds(2) else {
            resetObservation()
            return false
        }
        defer { lastSample = time }
        guard let lastSample else { return false }
        if time != lastSample {
            stalledFor = .zero
            // A seek is movement, but is not evidence of a healthy connection.
            let advance = time - lastSample
            if advance > .zero, advance <= elapsed * 4 {
                healthyFor += elapsed
                if healthyFor >= .seconds(60) { attempts = 0 }
            } else {
                healthyFor = .zero
            }
        } else {
            healthyFor = .zero
            stalledFor += elapsed
        }
        return stalledFor >= timeout
    }
}
