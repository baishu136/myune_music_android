package com.alesdrnz.mpv_audio_kit.media_session

internal class BackgroundServiceRecovery {
    var attempts = 0
        private set
    private var connectedAt: Long? = null

    fun reset() { attempts = 0; connectedAt = null }
    fun tryStart(): Boolean {
        if (attempts >= 3) return false
        attempts++
        return true
    }
    fun connected(now: Long) { connectedAt = now }
    fun disconnected(now: Long) {
        connectedAt?.let { if (now - it >= 10_000) attempts = 0 }
        connectedAt = null
    }
    fun retryDelay(): Long? = if (attempts >= 3) null
        else 250L shl (attempts - 1).coerceIn(0, 2)
}
