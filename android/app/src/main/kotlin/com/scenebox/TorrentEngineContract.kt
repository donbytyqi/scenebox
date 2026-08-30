package com.scenebox

/** Android equivalent of the original native TorrentEngine API. */
data class TorrentFile(
    val index: Int,
    val path: String,
    val offset: Long,
    val length: Long,
)

data class TorrentStats(
    val downloadRate: Double,
    val numPeers: Int,
    val numSeeds: Int,
    val progress: Double,
    val downloadedBytes: Long,
)

data class TorrentDiagnostics(
    val numPeers: Int,
    val numSeeds: Int,
    val numConnections: Int,
    val connectCandidates: Int,
    val listPeers: Int,
    val listSeeds: Int,
    val torrentState: String,
    val totalWanted: Long,
    val totalWantedDone: Long,
    val allTimeDownload: Long,
    val downloadRate: Double,
    val uploadRate: Double,
    val outgoingAttempts: Long,
    val incomingAccepts: Long,
    val connectFailures: Long,
    val dhtNodes: Int,
    val disconnectReasons: Map<String, Long>,
    val lastPeerSource: String,
)

interface TorrentEngineContract {
    val isActive: Boolean
    val hasMetadata: Boolean
    val pieceLength: Int
    val pieceCount: Int

    fun startMagnet(magnetUri: String, resumeData: ByteArray? = null)
    fun retryMetadataDiscovery()
    fun files(): List<TorrentFile>
    fun selectFile(fileIndex: Int)
    fun prepareStreaming(fileIndex: Int)
    fun beginStreamingSteadyState(fileIndex: Int)
    fun hasPiece(pieceIndex: Int): Boolean
    fun readPiece(pieceIndex: Int, callback: (ByteArray?) -> Unit)
    fun setPieceDeadline(pieceIndex: Int, milliseconds: Int)
    fun clearPieceDeadline(pieceIndex: Int)
    fun setPiecePriority(pieceIndex: Int, priority: Int)
    fun stats(): TorrentStats
    fun diagnostics(): TorrentDiagnostics
    fun saveResumeData(callback: (ByteArray?) -> Unit)
    fun pause()
    fun resume()
    fun stop()
}
