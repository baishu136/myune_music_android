package com.myune.music

import kotlin.math.abs
import kotlin.math.ceil

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
    var rate = 1.0
        private set

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

/** -1 means finished; zero means an advancing word needs the next display frame. */
internal fun desktopLyricFrameDelay(position: Double, words: List<DesktopLyricWord>, rate: Double): Long {
    var next = Double.POSITIVE_INFINITY
    for (word in words) {
        if (position >= word.start && position < word.end) return 0
        if (position < word.start) next = minOf(next, word.start)
    }
    return if (next.isFinite()) ceil((next - position) / rate.coerceAtLeast(.01))
        .coerceIn(1.0, Int.MAX_VALUE.toDouble()).toLong() else -1
}

internal fun fitDesktopLyricMultilineSize(maximum: Float, minimum: Float,
                                        fits: (Float) -> Boolean): Float {
    val floor = minimum.coerceIn(.1f, maximum.coerceAtLeast(.1f))
    if (fits(maximum)) return maximum
    if (!fits(floor)) return floor
    var low = floor
    var high = maximum
    repeat(10) {
        val mid = (low + high) * .5f
        if (fits(mid)) low = mid else high = mid
    }
    return low
}

internal object DesktopLyricMotion {
    const val EXIT_LEAD = 200.0
    const val ENTER_LEAD = 180.0
    const val ENTER_DURATION = 220.0
    fun enterStart(start: Double, afterExit: Boolean = false) =
        if (afterExit) start - EXIT_LEAD + EXIT_LEAD * .8 else start - ENTER_LEAD
    fun enter(position: Double, start: Double, afterExit: Boolean = false) =
        ((position - enterStart(start, afterExit)) / ENTER_DURATION).coerceIn(0.0, 1.0)
    fun exit(position: Double, next: Double) =
        ((position - next + EXIT_LEAD) / EXIT_LEAD).coerceIn(0.0, 1.0)
    fun spring(t: Double): Float {
        val x = t.coerceIn(0.0, 1.0) - 1.0
        return (1.0 + 2.3 * x * x * x + 1.3 * x * x).toFloat()
    }
    fun opacity(t: Double): Float {
        val x = (t / .8).coerceIn(0.0, 1.0)
        return (1.0 - (1.0 - x) * (1.0 - x) * (1.0 - x)).toFloat()
    }
}
