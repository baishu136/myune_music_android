package com.myune.music

import android.os.Build
import android.view.WindowManager

/** Window opacity, rather than View/text alpha, governs Android 12+ touch trust. */
internal object DesktopLyricsTouchPolicy {
    const val DEFAULT_MAXIMUM_OBSCURING_OPACITY = 0.8f

    data class State(val flags: Int, val alpha: Float)

    fun resolve(
        locked: Boolean,
        suppressed: Boolean,
        hasContent: Boolean,
        sdkInt: Int,
        maximumObscuringOpacity: Float,
    ): State {
        val passThrough = locked || suppressed || !hasContent
        val base = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
            WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
        // Some ROMs expose a stricter limit. Never exceed it or the documented
        // Android default, even when the service returns an invalid value.
        val safeOpacity = if (maximumObscuringOpacity.isFinite()) {
            maximumObscuringOpacity.coerceIn(0f, DEFAULT_MAXIMUM_OBSCURING_OPACITY)
        } else {
            DEFAULT_MAXIMUM_OBSCURING_OPACITY
        }
        return State(
            flags = if (passThrough) base or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE else base,
            alpha = if (passThrough && sdkInt >= Build.VERSION_CODES.S) safeOpacity else 1f,
        )
    }
}
