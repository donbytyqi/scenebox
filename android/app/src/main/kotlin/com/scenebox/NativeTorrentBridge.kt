package com.scenebox

import android.content.Context
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Flutter-facing bridge to the Android native torrent engine. */
class NativeTorrentBridge(private val context: Context) : MethodChannel.MethodCallHandler {
    private var activeMagnet: String? = null

    init {
        System.loadLibrary("scenebox_torrent")
    }

    private external fun nativeStart(magnet: String): Boolean
    private external fun nativeStop()
    private external fun nativeIsActive(): Boolean

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "torrent.start" -> {
                    val magnet = call.argument<String>("magnet")
                    if (magnet.isNullOrBlank()) {
                        result.error("INVALID_MAGNET", "A magnet URI is required", null)
                        return
                    }
                    if (!nativeStart(magnet)) {
                        result.error("TORRENT_START_FAILED", "Native torrent engine could not start", null)
                        return
                    }
                    activeMagnet = magnet
                    result.success(mapOf("status" to "started"))
                }
                "torrent.stop" -> {
                    nativeStop()
                    activeMagnet = null
                    result.success(null)
                }
                "torrent.status" -> result.success(
                    mapOf("active" to nativeIsActive(), "magnet" to activeMagnet)
                )
                else -> result.notImplemented()
            }
        } catch (error: UnsatisfiedLinkError) {
            result.error("NATIVE_ENGINE_UNAVAILABLE", error.message, null)
        } catch (error: Exception) {
            result.error("TORRENT_ERROR", error.message, null)
        }
    }
}
