package com.scenebox

/**
 * Maps an HTTP byte range in a selected torrent file to the torrent pieces
 * that must be available before Media3 can read the requested bytes.
 */
class TorrentRangeMapper(
    private val fileOffset: Long,
    private val fileLength: Long,
    private val pieceLength: Int,
) {
    init {
        require(fileOffset >= 0)
        require(fileLength >= 0)
        require(pieceLength > 0)
    }

    data class PieceRange(val first: Int, val last: Int) {
        fun asList(): List<Int> = (first..last).toList()
    }

    fun clamp(range: RangeRequest): RangeRequest? {
        if (range.start >= fileLength) return null
        val end = minOf(range.end ?: (fileLength - 1), fileLength - 1)
        return RangeRequest(range.start, end)
    }

    fun pieces(range: RangeRequest): PieceRange? {
        val bounded = clamp(range) ?: return null
        val absoluteStart = fileOffset + bounded.start
        val absoluteEnd = fileOffset + bounded.end!!
        val first = (absoluteStart / pieceLength).toInt()
        val last = (absoluteEnd / pieceLength).toInt()
        return PieceRange(first, last)
    }
}
