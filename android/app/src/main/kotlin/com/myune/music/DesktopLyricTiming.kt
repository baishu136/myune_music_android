package com.myune.music

import kotlin.math.abs

internal data class DesktopLyricWord(
    val offset: Int, val length: Int, val start: Double, val end: Double,
) {
    fun progress(position: Double): Float = when {
        position < start -> 0f
        end <= start || position >= end -> 1f
        else -> ((position - start) / (end - start)).toFloat().coerceIn(0f, 1f)
    }
}

internal class DesktopLyricClock {
    private var key = ""
    private var anchor = 0.0
    private var at = 0L
    var playing = false
        private set
    private var rate = 1.0

    fun position(now: Long): Double =
        anchor + if (playing) (now - at).coerceAtLeast(0) * rate else 0.0

    fun update(id: String, position: Double, play: Boolean, speed: Double, now: Long) {
        val next = if (position.isFinite()) position.coerceAtLeast(0.0) else 0.0
        val predicted = position(now)
        // Ignore tiny timestamp jitter, but seek identities and transport changes
        // always apply immediately. No easing across an explicit seek.
        anchor = if (id == key && playing && play && rate == speed &&
            abs(predicted - next) <= 120.0) predicted else next
        key = id
        playing = play
        rate = if (speed.isFinite() && speed > 0) speed else 1.0
        at = now
    }
}

internal fun fitDesktopLyricSize(
    maximum: Float, available: Float, measure: (Float) -> Float,
): Float {
    if (maximum <= 0f || available <= 0f) return 0.1f
    if (measure(maximum) <= available) return maximum
    var low = 0.1f
    var high = maximum
    repeat(16) {
        val middle = (low + high) * 0.5f
        if (measure(middle) <= available) low = middle else high = middle
    }
    return low
}
