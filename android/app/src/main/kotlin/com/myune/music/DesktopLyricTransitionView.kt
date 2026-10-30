package com.myune.music

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Typeface
import android.os.SystemClock
import android.os.Build
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import kotlin.math.ceil

/** Two prepared text layers; animation changes transforms only, never text layout. */
internal class DesktopLyricTransitionView(context: Context) : FrameLayout(context) {
    private val layers = Array(2) { OutlinedLyricTextView(context) }
    private val clock = DesktopLyricClock()
    private var current = 0
    private var currentKey = ""
    private var nextKey: String? = null
    private var timeline = ""
    private var enteredKey: String? = null
    private var currentStart: Double? = null
    private var nextStart: Double? = null
    private var enabled = true
    private var afterExit = false
    private var hasNext = false
    private val frame = Runnable { updateMotion() }

    init {
        clipChildren = false
        clipToPadding = false
        for (layer in layers) {
            layer.includeFontPadding = false
            layer.breakStrategy = android.text.Layout.BREAK_STRATEGY_HIGH_QUALITY
            layer.hyphenationFrequency = android.text.Layout.HYPHENATION_FREQUENCY_NONE
            val density = resources.displayMetrics.density
            layer.setPadding((8 * density).toInt(), (6 * density).toInt(),
                (8 * density).toInt(), (6 * density).toInt())
            addView(layer, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT, Gravity.TOP))
        }
        layers[1].alpha = 0f
    }

    fun configure(color: Int, size: Float, face: Typeface, autoSize: Boolean, alignment: String,
                  stroke: Boolean, width: Float, outline: Int, opacity: Float,
                  maximumLines: Int, minimumSize: Float) {
        for (layer in layers) layer.configure(color, size, face, autoSize, alignment,
            stroke, width, outline, opacity, maximumLines, minimumSize)
    }

    fun updatePlayback(values: Map<String, Any?>) {
        val now = SystemClock.uptimeMillis()
        val newTimeline = values["timelineKey"]?.toString() ?: timeline
        clock.update(newTimeline, (values["positionMs"] as? Number)?.toDouble() ?: 0.0,
            values["isPlaying"] == true,
            (values["playbackRate"] as? Number)?.toDouble() ?: 1.0, now)
        if (values["clockOnly"] == true) {
            // Keep both prepared layers on the same media clock.
            for (layer in layers) layer.updatePlayback(values)
            updateMotion()
            return
        }
        val key = values["lyricKey"]?.toString().orEmpty()
        if (newTimeline != timeline || (key != currentKey && key != nextKey)) {
            current = 0
            enteredKey = null
        } else if (key != currentKey && key == nextKey) {
            current = 1 - current
            enteredKey = key
        }
        timeline = newTimeline
        currentKey = key
        enabled = values["transition"] == true &&
            (Build.VERSION.SDK_INT < 26 || ValueAnimator.areAnimatorsEnabled())
        afterExit = values["karaoke"] == true
        if (!enabled) enteredKey = null
        currentStart = (values["lineStartMs"] as? Number)?.toDouble()
        nextStart = (values["nextTimestampMs"] as? Number)?.toDouble()
        nextKey = values["nextLyricKey"]?.toString()
        hasNext = nextKey != null && nextStart != null
        layers[current].updatePlayback(values)
        layers[current].visibility = View.VISIBLE
        layers[1 - current].visibility = if (enabled && hasNext) View.VISIBLE else View.GONE
        if (enabled && hasNext) {
            layers[1 - current].updatePlayback(values + mapOf(
                "lyric" to values["nextLyric"], "words" to values["nextWords"],
                "lyricKey" to nextKey,
            ))
        }
        layers[current].bringToFront()
        updateMotion()
    }

    private fun transform(view: View, scale: Float, opacity: Float) {
        view.scaleX = scale
        view.scaleY = scale
        view.alpha = opacity.coerceIn(0f, 1f)
    }

    private fun updateMotion() {
        removeCallbacks(frame)
        val primary = layers[current]
        val upcoming = layers[1 - current]
        if (!enabled) {
            transform(primary, 1f, 1f)
            transform(upcoming, 1f, 0f)
            return
        }
        val position = clock.position(SystemClock.uptimeMillis())
        val entering = if (enteredKey == currentKey && currentStart != null)
            DesktopLyricMotion.enter(position, currentStart!!, afterExit) else 1.0
        val exiting = nextStart?.let { DesktopLyricMotion.exit(position, it) } ?: 0.0
        transform(primary,
            (.82f + .18f * DesktopLyricMotion.spring(entering)) *
                (1f - .18f * DesktopLyricMotion.spring(exiting)),
            DesktopLyricMotion.opacity(entering) * (1f - DesktopLyricMotion.opacity(exiting)))
        val upcomingProgress = nextStart?.let { DesktopLyricMotion.enter(position, it, afterExit) } ?: 0.0
        transform(upcoming, .82f + .18f * DesktopLyricMotion.spring(upcomingProgress),
            if (hasNext) DesktopLyricMotion.opacity(upcomingProgress) else 0f)
        if (!clock.playing || !isAttachedToWindow || !isShown || windowVisibility != View.VISIBLE) return
        val inMotion = enteredKey == currentKey && currentStart != null &&
            entering < 1 && position >= DesktopLyricMotion.enterStart(currentStart!!, afterExit) ||
            hasNext && nextStart != null &&
            position >= nextStart!! - DesktopLyricMotion.EXIT_LEAD &&
            position < DesktopLyricMotion.enterStart(nextStart!!, afterExit) + DesktopLyricMotion.ENTER_DURATION
        if (inMotion) postOnAnimation(frame) else {
            val wake = nextStart?.minus(DesktopLyricMotion.EXIT_LEAD)
            if (wake != null && wake > position) {
                postDelayed(frame, ceil((wake - position) / clock.rate).toLong().coerceAtLeast(1))
            }
        }
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(frame)
        super.onDetachedFromWindow()
    }
    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        updateMotion()
    }
    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        removeCallbacks(frame)
        if (visibility == View.VISIBLE) updateMotion()
    }
}
