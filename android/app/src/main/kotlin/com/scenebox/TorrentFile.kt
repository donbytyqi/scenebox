package com.scenebox

data class TorrentFile(
    val index: Int,
    val path: String,
    val offset: Long,
    val length: Long,
)
