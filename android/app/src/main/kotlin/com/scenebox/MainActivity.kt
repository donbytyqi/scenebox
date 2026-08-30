package com.scenebox

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "scenebox/android"
    private val torrentChannelName = "scenebox/torrent"
    private var channel: MethodChannel? = null
    private var torrentChannel: MethodChannel? = null
    private var player: PlayerBridge? = null
    private var torrent: TorrentMethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        player = PlayerBridge(this)
        channel?.setMethodCallHandler(PlaybackChannel(this, player!!))

        torrentChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, torrentChannelName)
        torrent = TorrentMethodChannel(this)
        torrent?.attach(torrentChannel!!)

        intent?.data?.toString()?.let { link ->
            channel?.invokeMethod("initialDeepLink", link)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.data?.toString()?.let {
            channel?.invokeMethod("onDeepLink", it)
        }
    }

    override fun onDestroy() {
        torrent?.close()
        torrent = null
        torrentChannel?.setMethodCallHandler(null)
        torrentChannel = null
        player?.release()
        player = null
        channel?.setMethodCallHandler(null)
        channel = null
        super.onDestroy()
    }
}
