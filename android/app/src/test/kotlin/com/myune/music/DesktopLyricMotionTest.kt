package com.myune.music

import org.junit.Assert.*
import org.junit.Test

class DesktopLyricMotionTest {
    @Test fun karaokeEntryWaitsForEightyPercentOfExit() {
        val next = 2000.0
        for (hz in listOf(60, 90, 120)) {
            for (frame in 0..hz) {
                val position = 1800.0 + frame * 200.0 / hz
                val exit = DesktopLyricMotion.exit(position, next)
                val enter = DesktopLyricMotion.enter(position, next, true)
                if (exit <= .8) assertEquals(0.0, enter, .000001)
                else assertTrue(enter > 0)
            }
        }
        assertEquals(1960.0, DesktopLyricMotion.enterStart(next, true), 0.0)
        assertEquals(0.0, DesktopLyricMotion.enter(1960.0, next, true), 0.0)
        assertEquals(1.0, DesktopLyricMotion.enter(2180.0, next, true), 0.0)
        assertTrue(DesktopLyricMotion.enter(1850.0, next) > 0)
    }
    @Test fun exactLeadTimesAndOpacityCompletion() {
        assertEquals(0.0, DesktopLyricMotion.exit(1799.0, 2000.0), 0.0)
        assertTrue(DesktopLyricMotion.exit(1801.0, 2000.0) > 0)
        assertEquals(1.0, DesktopLyricMotion.exit(2000.0, 2000.0), 0.0)
        assertEquals(0.0, DesktopLyricMotion.enter(1820.0, 2000.0), 0.0)
        assertTrue(DesktopLyricMotion.enter(1821.0, 2000.0) > 0)
        assertEquals(1.0, DesktopLyricMotion.enter(2040.0, 2000.0), 0.0)
        assertEquals(1f, DesktopLyricMotion.opacity(.8), 0f)
        assertEquals(1f, DesktopLyricMotion.opacity(1.0), 0f)
        assertEquals(0f, DesktopLyricMotion.opacity(0.0), 0f)
    }
    @Test fun springIsBoundedAndOpacityMonotoneAtAllRefreshRates() {
        for (hz in listOf(60, 90, 120)) {
            var previous = 0f
            for (frame in 0..hz) {
                val t = frame.toDouble() / hz
                val spring = DesktopLyricMotion.spring(t)
                val alpha = DesktopLyricMotion.opacity(t)
                assertTrue(spring in 0f..1.08f)
                assertTrue(alpha >= previous)
                assertTrue(alpha in 0f..1f)
                previous = alpha
            }
        }
        assertEquals(0f, DesktopLyricMotion.spring(0.0), .000001f)
        assertEquals(1f, DesktopLyricMotion.spring(1.0), 0f)
        assertTrue(DesktopLyricMotion.spring(.7) > 1f)
    }
    @Test fun pauseAndRateUseMediaTimeAndSeekNeverReplaysAnOldTransition() {
        val clock = DesktopLyricClock()
        clock.update("song:0", 1850.0, true, 1.0, 0)
        clock.update("song:0", 1900.0, false, 1.0, 50)
        val frozen = DesktopLyricMotion.enter(clock.position(50), 2000.0)
        assertEquals(frozen, DesktopLyricMotion.enter(clock.position(10000), 2000.0), 0.0)
        clock.update("song:0", 1900.0, true, 2.0, 10000)
        assertEquals(1.0, DesktopLyricMotion.enter(clock.position(10070), 2000.0), 0.0)
        clock.update("song:seek1", 100.0, true, 1.0, 10070)
        assertEquals(0.0, DesktopLyricMotion.enter(clock.position(10070), 2000.0), 0.0)
    }
    @Test fun multilineFitRespectsFloorCeilingAndRecoversForShortLyrics() {
        assertEquals(30f, fitDesktopLyricMultilineSize(30f, 12f) { true }, 0f)
        assertEquals(12f, fitDesktopLyricMultilineSize(30f, 12f) { false }, 0f)
        assertEquals(30f, fitDesktopLyricMultilineSize(30f, 40f) { false }, 0f)
        val fitted = fitDesktopLyricMultilineSize(40f, 10f) { it * 20 <= 600 }
        assertTrue(fitted <= 30f)
        assertTrue(fitted >= 29.9f)
    }
}
