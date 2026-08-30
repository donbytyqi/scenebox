package com.scenebox

import java.io.Closeable
import java.io.OutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.charset.StandardCharsets
import java.util.concurrent.Executors

/** Localhost HTTP range server for the selected torrent file. */
class TorrentHttpServer(private val reader: TorrentByteReader) : Closeable {
    private val executor = Executors.newCachedThreadPool()
    private var serverSocket: ServerSocket? = null
    @Volatile private var running = false
    @Volatile private var selectedFile: TorrentFile? = null

    fun selectFile(file: TorrentFile) { selectedFile = file }

    fun start(): Int {
        if (running) return serverSocket?.localPort ?: -1
        serverSocket = ServerSocket(0, 16, InetAddress.getLoopbackAddress())
        running = true
        executor.execute {
            while (running) {
                try {
                    val socket = serverSocket?.accept() ?: break
                    executor.execute { handle(socket) }
                } catch (_: Exception) { if (!running) break }
            }
        }
        return serverSocket!!.localPort
    }

    private fun handle(socket: Socket) {
        socket.use { client ->
            val input = client.getInputStream().bufferedReader(StandardCharsets.ISO_8859_1)
            val requestLine = input.readLine() ?: return
            val headers = mutableMapOf<String, String>()
            while (true) {
                val line = input.readLine() ?: break
                if (line.isEmpty()) break
                val colon = line.indexOf(':')
                if (colon > 0) headers[line.substring(0, colon).trim().lowercase()] = line.substring(colon + 1).trim()
            }
            val out = client.getOutputStream()
            if (!requestLine.startsWith("GET ")) { writeError(out, 405, "Method Not Allowed"); return }
            val file = selectedFile ?: run { writeError(out, 503, "No file selected"); return }
            val rangeHeader = headers["range"]
            val requested = RangeRequest.parse(rangeHeader) ?: RangeRequest(0, file.length - 1)
            val bounded = TorrentRangeMapper(file.offset, file.length, reader.pieceLength).clamp(requested)
                ?: run { writeError(out, 416, "Range Not Satisfiable"); return }
            val start = bounded.start
            val end = bounded.end ?: start
            val length = end - start + 1
            val status = if (rangeHeader == null) "200 OK" else "206 Partial Content"
            val response = buildString {
                append("HTTP/1.1 $status\r\n")
                append("Content-Type: video/mp4\r\nAccept-Ranges: bytes\r\n")
                append("Content-Length: $length\r\n")
                if (rangeHeader != null) append("Content-Range: bytes $start-$end/${file.length}\r\n")
                append("Connection: close\r\n\r\n")
            }
            out.write(response.toByteArray(StandardCharsets.ISO_8859_1))
            reader.stream(file, start, length, out)
            out.flush()
        }
    }

    private fun writeError(out: OutputStream, code: Int, message: String) {
        val body = message.toByteArray(StandardCharsets.UTF_8)
        out.write("HTTP/1.1 $code $message\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n".toByteArray(StandardCharsets.ISO_8859_1))
        out.write(body)
    }

    override fun close() {
        running = false
        serverSocket?.close()
        serverSocket = null
        executor.shutdownNow()
    }
}

interface TorrentByteReader {
    val pieceLength: Int
    fun stream(file: TorrentFile, fileOffset: Long, length: Long, output: OutputStream)
}
