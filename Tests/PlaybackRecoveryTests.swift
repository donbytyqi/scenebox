import Foundation

// Run without a device or VLC: swiftc WatchBox/Features/Player/PlaybackRecovery.swift
// Tests/PlaybackRecoveryTests.swift -o /tmp/playback-recovery-tests && /tmp/playback-recovery-tests
@main
struct PlaybackRecoveryTests {
    static func main() {
        var recovery = PlaybackRecovery()
        recovery.position = .seconds(600)
        assert(recovery.endedPrematurely(duration: .seconds(3600)))
        assert(!recovery.endedPrematurely(duration: .zero), "Unknown duration is not proof of truncation")
        assert(!recovery.endedPrematurely(duration: .seconds(604)), "Normal endings must not restart")

        for attempt in 1...3 {
            assert(recovery.reserveRetry(limit: 3))
            assert(recovery.attempts == attempt)
            assert(recovery.position == .seconds(600), "Reconnect must preserve the resume point")
            assert(!tick(&recovery, at: 0))
            for _ in 0..<19 { assert(!tick(&recovery, at: 0)) }
            assert(tick(&recovery, at: 0), "A connection that never opens must time out")
        }
        assert(!recovery.reserveRetry(limit: 3), "Repeated failures must stop retrying")

        recovery.resetObservation()
        for second in 0...59 { assert(!tick(&recovery, at: second)) }
        assert(recovery.attempts == 3, "Brief playback must not replenish retries")
        assert(!tick(&recovery, at: 60))
        assert(recovery.attempts == 0, "Sustained playback allows recovery from a later outage")

        for _ in 0..<120 { assert(!tick(&recovery, at: 60, expected: false)) }
        assert(!tick(&recovery, at: 60), "Resuming after a long pause starts a fresh timeout")
        for _ in 0..<19 { assert(!tick(&recovery, at: 60)) }
        assert(!tick(&recovery, at: 10), "A backward seek resets the stall timer")
        for _ in 0..<19 { assert(!tick(&recovery, at: 10)) }
        assert(tick(&recovery, at: 10))

        recovery.resetObservation()
        assert(!tick(&recovery, at: 10))
        for _ in 0..<10 { assert(!tick(&recovery, at: 10)) }
        assert(!tick(&recovery, at: 11), "Buffering that resolves needs no reconnect")
        for _ in 0..<19 { assert(!tick(&recovery, at: 11)) }
        assert(tick(&recovery, at: 11))

        assert(!recovery.observe(time: .seconds(11), elapsed: .seconds(90),
                                 expectedToAdvance: true, timeout: .seconds(20)),
               "Time spent suspended must not trigger a reconnect")
        assert(!tick(&recovery, at: 11))

        recovery.resetAttempts()
        assert(recovery.attempts == 0)
        assert(recovery.position == .seconds(600), "Manual Retry must keep the resume point")
        for _ in 0..<5 { assert(recovery.reserveRetry(limit: 5)) }
        assert(!recovery.reserveRetry(limit: 5), "Local torrent opening retains its retry limit")
        print("Playback recovery checks passed")
    }

    private static func tick(_ recovery: inout PlaybackRecovery, at seconds: Int,
                             expected: Bool = true) -> Bool {
        recovery.observe(time: .seconds(seconds), elapsed: .seconds(1),
                         expectedToAdvance: expected, timeout: .seconds(20))
    }
}
