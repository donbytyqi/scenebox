package com.scenebox

/** Parsed HTTP byte range. End is inclusive. */
data class RangeRequest(val start: Long, val end: Long?) {
    companion object {
        fun parse(value: String?): RangeRequest? {
            if (value == null || !value.startsWith("bytes=")) return null
            val spec = value.removePrefix("bytes=").split(',', limit = 2).firstOrNull() ?: return null
            val parts = spec.split('-', limit = 2)
            if (parts.size != 2) return null
            val start = parts[0].toLongOrNull() ?: return null
            val end = parts[1].takeIf { it.isNotBlank() }?.toLongOrNull()
            if (start < 0 || (end != null && end < start)) return null
            return RangeRequest(start, end)
        }
    }
}
