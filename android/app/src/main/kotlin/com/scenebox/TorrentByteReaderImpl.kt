package com.scenebox

import java.io.OutputStream

/**
 * Bounded reader that turns a selected torrent-file range into a Media3
 * compatible byte stream. NativePieceReader supplies complete torrent pieces.
 */
class TorrentByteReaderImpl(
    private val native: NativePieceReader,
    override val pieceLength: Int,
    private val maxPieceWaits: Int = 60,
) : TorrentByteReader {

    override fun stream(file: TorrentFile, fileOffset: Long, length: Long, output: OutputStream) {
        require(fileOffset >= 0 && length >= 0)
        require(fileOffset < file.length || length == 0L)
        require(fileOffset + length <= file.length)

        if (length == 0L) return

        val mapper = TorrentRangeMapper(file.offset, file.length, pieceLength)
        val range = RangeRequest(fileOffset, fileOffset + length - 1)
        val pieces = mapper.pieces(range) ?: throw IllegalArgumentException("Invalid torrent range")

        PieceScheduler(native.bridge, deadlineMs = 8_000).prioritize(range, mapper)
        try {
            var remaining = length
            var cursor = fileOffset
            for (piece in pieces.asList()) {
                waitForPiece(piece)
                val data = native.readPiece(piece)
                    ?: throw IllegalStateException("Torrent piece $piece could not be read")

                val absolutePieceStart = (file.offset / pieceLength) * pieceLength.toLong() +
                    (piece - (file.offset / pieceLength).toInt()) * pieceLength.toLong()
                val startInPiece = maxOf(0L, cursor + file.offset - absolutePieceStart).toInt()
                val available = minOf(data.size - startInPiece, remaining.toInt())
                if (available <= 0) continue

                output.write(data, startInPiece, available)
                cursor += available
                remaining -= available
                if (remaining == 0L) break
            }
        } finally {
            PieceScheduler(native.bridge, deadlineMs = 8_000).clear(pieces)
        }
    }

    private fun waitForPiece(piece: Int) {
        repeat(maxPieceWaits) {
            if (native.hasPiece(piece)) return
            Thread.sleep(250)
        }
        throw IllegalStateException("Timed out waiting for torrent piece $piece")
    }

    class NativePieceReader(
        val bridge: PieceControl,
        private val read: (Int) -> ByteArray?,
        private val available: (Int) -> Boolean,
    ) {
        fun readPiece(piece: Int): ByteArray? = read(piece)
        fun hasPiece(piece: Int): Boolean = available(piece)
    }

    interface PieceControl {
        fun setPiecePriority(piece: Int, priority: Int)
        fun setPieceDeadline(piece: Int, deadlineMs: Int)
        fun clearPieceDeadline(piece: Int)
    }
}
