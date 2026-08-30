package com.scenebox

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer

/** Small native playback facade used by Flutter through MainActivity. */
class PlayerBridge(context: Context) {
    private val player = ExoPlayer.Builder(context).build()

    fun setUrl(url: String) {
        player.setMediaItem(MediaItem.fromUri(url))
        player.prepare()
    }

    fun play() = player.play()
    fun pause() = player.pause()
    fun release() = player.release()
}
