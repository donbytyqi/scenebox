package com.scenebox

/** Coordinates piece priorities for a Media3 byte-range request. */
class PieceScheduler(
    private val engine: NativeTorrentBridge,
    private val deadlineMs: Int = 8_000,
) {
    fun prioritize(range: RangeRequest, mapper: TorrentRangeMapper): TorrentRangeMapper.PieceRange? {
        val pieces = mapper.pieces(range) ?: return null
        pieces.asList().forEachIndexed { index, piece ->
            val priority = when {
                index == 0 -> 7
                index < 4 -> 6
                else -> 4
            }
            engine.setPiecePriority(piece, priority)
            engine.setPieceDeadline(piece, deadlineMs + index * 500)
        }
        return pieces
    }

    fun clear(range: TorrentRangeMapper.PieceRange) {
        range.asList().forEach { engine.clearPieceDeadline(it) }
    }
}
