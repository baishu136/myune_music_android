package com.myune.music

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DesktopLyricTimingTest {
    @Test fun animationSleepsDuringGapsAndStopsAtEnd() {
        val words = listOf(DesktopLyricWord(0, 1, 2000.0, 3000.0),
            DesktopLyricWord(1, 1, 7000.0, 8000.0))
        assertEquals(2000L, desktopLyricFrameDelay(0.0, words, 1.0))
        assertEquals(0L, desktopLyricFrameDelay(2500.0, words, 1.0))
        assertEquals(2000L, desktopLyricFrameDelay(3000.0, words, 2.0))
        assertEquals(-1L, desktopLyricFrameDelay(8000.0, words, 1.0))
        assertEquals(-1L, desktopLyricFrameDelay(0.0, emptyList(), 1.0))
        // Provider order and overlaps do not disable an active token.
        assertEquals(0L, desktopLyricFrameDelay(2500.0, words.reversed(), 1.0))
    }
    @Test fun playbackPauseResumeRateAndSeek() {
        val clock = DesktopLyricClock()
        clock.update("a", 1000.0, true, 1.0, 100)
        assertEquals(1500.0, clock.position(600), 0.0)
        clock.update("a", 1500.0, false, 1.0, 600)
        assertEquals(1500.0, clock.position(1600), 0.0)
        clock.update("a", 1500.0, true, 2.0, 1600)
        assertEquals(2500.0, clock.position(2100), 0.0)
        clock.update("seek1", 100.0, true, 2.0, 2100)
        assertEquals(100.0, clock.position(2100), 0.0)
        clock.update("track2", 0.0, true, 1.0, 2100)
        assertEquals(200.0, clock.position(2300), 0.0)
    }
    @Test fun periodicJitterDoesNotRewindButDiscontinuityApplies() {
        val clock = DesktopLyricClock()
        clock.update("a", 1000.0, true, 1.0, 0)
        clock.update("a", 1740.0, true, 1.0, 800)
        assertEquals(1800.0, clock.position(800), 0.0)
        clock.update("a", 500.0, true, 1.0, 1000)
        assertEquals(500.0, clock.position(1000), 0.0)
    }
    @Test fun animationSamplesAreContinuousAcrossRefreshRates() {
        for (hz in listOf(60, 90, 120)) {
            val clock = DesktopLyricClock()
            clock.update("a", 0.0, true, 1.0, 0)
            val word = DesktopLyricWord(0, 1, 0.0, 2000.0)
            var previous = 0f
            for (frame in 0..hz * 2) {
                val progress = word.progress(clock.position((frame * 1000.0 / hz).toLong()))
                assertTrue(progress >= previous)
                assertTrue(progress - previous < .01f)
                previous = progress
            }
            assertEquals(1f, previous, 0f)
        }
    }
    @Test fun perLineFitNeverEnlargesAndRecoversForShortNextLine() {
        val long = fitDesktopLyricSize(120f, 300f) { it * 20 }
        assertEquals(15f, long, .003f)
        val short = fitDesktopLyricSize(120f, 300f) { it * 2 }
        assertEquals(120f, short, 0f)
        assertTrue(long * 20 <= 300)
    }
    @Test fun nonlinearMeasurementReservesOutlineAndHandlesTinyWidth() {
        val size = fitDesktopLyricSize(120f, 1f) { it * it * 2 }
        assertTrue(size * size * 2 <= 1f)
        assertTrue(size > .1f)
    }
}
