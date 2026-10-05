package com.myune.music

import android.view.WindowManager
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DesktopLyricsTouchPolicyTest {
    private fun state(
        locked: Boolean = false,
        suppressed: Boolean = false,
        hasContent: Boolean = true,
        sdk: Int = 31,
        maximum: Float = 0.8f,
    ) = DesktopLyricsTouchPolicy.resolve(locked, suppressed, hasContent, sdk, maximum)

    private fun assertPassThrough(value: DesktopLyricsTouchPolicy.State, maximum: Float) {
        assertTrue(value.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE != 0)
        assertTrue(value.flags and WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE != 0)
        assertTrue(value.alpha <= maximum)
    }

    @Test fun lockAndUnlockRestoreTouchTrustAndOpacity() {
        for (sdk in listOf(31, 32, 33, 34, 35, 36)) {
            assertPassThrough(state(locked = true, sdk = sdk), 0.8f)
            val unlocked = state(sdk = sdk)
            assertEquals(0, unlocked.flags and WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE)
            assertEquals(1f, unlocked.alpha, 0f)
        }
    }

    @Test fun olderAndroidKeepsOriginalBrightnessButStillPassesTouches() {
        for (sdk in listOf(24, 26, 29, 30)) {
            val locked = state(locked = true, sdk = sdk)
            assertPassThrough(locked, 1f)
            assertEquals(1f, locked.alpha, 0f)
        }
    }

    @Test fun stricterSystemLimitsAreRespectedIncludingZero() {
        for (limit in listOf(0f, 0.4f, 0.6f, 0.8f)) {
            assertPassThrough(state(locked = true, maximum = limit), limit)
            assertEquals(limit, state(locked = true, maximum = limit).alpha, 0f)
        }
    }

    @Test fun invalidOrLargerLimitsUseConservativeDefault() {
        for (limit in listOf(Float.NaN, Float.POSITIVE_INFINITY, Float.NEGATIVE_INFINITY, 1f)) {
            assertEquals(0.8f, state(locked = true, maximum = limit).alpha, 0f)
        }
        assertEquals(0f, state(locked = true, maximum = -1f).alpha, 0f)
    }

    @Test fun foregroundSuppressionAndCloseFadeCannotLeaveOpaqueHitBlocker() {
        assertPassThrough(state(suppressed = true), 0.8f)
        assertPassThrough(state(hasContent = false), 0.8f)
        // Returning to the background while still locked remains safe;
        // unlocking afterwards restores the interactive state.
        assertPassThrough(state(locked = true, suppressed = false), 0.8f)
        assertEquals(1f, state().alpha, 0f)
    }
}
