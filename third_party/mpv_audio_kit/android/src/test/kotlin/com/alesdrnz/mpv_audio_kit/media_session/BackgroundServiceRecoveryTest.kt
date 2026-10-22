package com.alesdrnz.mpv_audio_kit.media_session

import org.junit.jupiter.api.Assertions.*
import org.junit.jupiter.api.Test

class BackgroundServiceRecoveryTest {
    @Test fun `failed connections stop after three attempts`() {
        val p = BackgroundServiceRecovery()
        assertTrue(p.tryStart()); assertEquals(250L, p.retryDelay())
        assertTrue(p.tryStart()); assertEquals(500L, p.retryDelay())
        assertTrue(p.tryStart()); assertNull(p.retryDelay())
        repeat(100) { assertFalse(p.tryStart()) }
    }
    @Test fun `rapid connect disconnect does not reset failure budget`() {
        val p = BackgroundServiceRecovery()
        repeat(3) {
            assertTrue(p.tryStart()); p.connected(1000); p.disconnected(1001)
        }
        assertFalse(p.tryStart())
    }
    @Test fun `stable connection gets a fresh budget on later disconnect`() {
        val p = BackgroundServiceRecovery()
        repeat(3) { assertTrue(p.tryStart()) }
        p.connected(1000); p.disconnected(11000)
        assertTrue(p.tryStart()); assertEquals(1, p.attempts)
    }
    @Test fun `explicit resume resets previous failures`() {
        val p = BackgroundServiceRecovery()
        repeat(3) { p.tryStart() }
        p.reset(); assertTrue(p.tryStart()); assertEquals(1, p.attempts)
    }
}
