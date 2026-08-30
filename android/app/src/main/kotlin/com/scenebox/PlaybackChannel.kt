package com.scenebox

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class PlaybackChannel(
    private val context: Context,
    private val player: PlayerBridge,
) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "player.setUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) {
                    result.error("INVALID_URL", "A media URL is required", null)
                    return
                }
                player.setUrl(url)
                result.success(null)
            }
            "player.play" -> { player.play(); result.success(null) }
            "player.pause" -> { player.pause(); result.success(null) }
            "player.release" -> { player.release(); result.success(null) }
            else -> result.notImplemented()
        }
    }
}
