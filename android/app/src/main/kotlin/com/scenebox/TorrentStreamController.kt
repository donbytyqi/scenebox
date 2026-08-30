package com.scenebox

import java.util.concurrent.atomic.AtomicBoolean

/** Owns the lifecycle of the localhost torrent media endpoint. */
class TorrentStreamController(
    private val reader: TorrentByteReader,
) : AutoCloseable {
    private var server: TorrentHttpServer? = null
    private val started = AtomicBoolean(false)

    @Synchronized
    fun start(file: TorrentFile): String {
        if (server == null) server = TorrentHttpServer(reader)
        server!!.selectFile(file)
        val port = server!!.start()
        started.set(true)
        return "http://127.0.0.1:$port/video"
    }

    @Synchronized
    fun stop() {
        server?.close()
        server = null
        started.set(false)
    }

    fun isRunning(): Boolean = started.get()

    override fun close() = stop()
}
