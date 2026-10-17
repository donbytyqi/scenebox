import SwiftUI

@main
struct ChromeVisibilityTests {
    @MainActor
    static func main() async {
        let normal = ChromeVisibility()
        let held = ChromeVisibility()
        let refreshed = ChromeVisibility()
        let cancelled = ChromeVisibility()
        for chrome in [normal, held, refreshed, cancelled] { chrome.playbackStarted() }

        let normalTimer = Task { await normal.autoHide() }
        let heldTimer = Task { await held.autoHide() }
        let oldTimer = Task { await refreshed.autoHide() }
        let cancelledTimer = Task { await cancelled.autoHide() }
        try? await Task.sleep(for: .milliseconds(100))

        held.holdVisible()
        refreshed.interacted(autoHide: true)
        cancelledTimer.cancel()

        await normalTimer.value
        await heldTimer.value
        await oldTimer.value
        await cancelledTimer.value
        assert(!normal.isVisible, "Controls should hide after four seconds")
        assert(held.isVisible, "A pending hide must not dismiss an open panel")
        assert(refreshed.isVisible, "An old timer must not hide newly interacted controls")
        assert(cancelled.isVisible, "Cancelled timers must not hide controls")

        held.releaseHold(autoHide: true)
        assert(held.autoHideID != nil)
        held.hide()
        held.reveal(autoHide: false)
        assert(held.isVisible && held.autoHideID == nil, "Paused controls stay visible")
        held.viewDisappeared()
        assert(held.autoHideID == nil)
        print("Chrome visibility checks passed")
    }
}
