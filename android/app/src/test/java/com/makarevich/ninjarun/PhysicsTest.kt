package com.makarevich.ninjarun

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Same checks the iOS physics was tuned against, so both versions play identically. */
class PhysicsTest {
    private val floorRow = "#" + ".".repeat(COLS - 2) + "#"
    private val solid = "#".repeat(COLS)
    private fun flat() = LevelMap((List(ROWS - 2) { floorRow } + floorRow + solid).joinToString("\n"))

    private fun settle(p: Player, map: LevelMap) = repeat(30) { p.step(InputState(), map) }

    private fun jumpRise(holdFrames: Int): Float {
        val map = flat()
        val p = Player(Vec(15 * TS + 12, 1.5f * TS))
        settle(p, map)
        val y0 = p.pos.y
        var maxY = y0
        for (f in 0 until 400) {
            p.step(InputState(0, f < holdFrames, f == 0), map)
            maxY = maxOf(maxY, p.pos.y)
        }
        return maxY - y0
    }

    @Test fun jumpHeights() {
        assertEquals(94f, jumpRise(200), 2f)   // hold: ~4 tiles
        assertEquals(30f, jumpRise(1), 2f)     // tap: ~1.3 tiles
    }

    private fun survivesFall(tiles: Int): Boolean {
        val map = flat()
        val p = Player(Vec(15 * TS + 12, 1.5f * TS))
        p.pos = Vec(p.pos.x, p.pos.y + tiles * TS)
        repeat(400) { if (p.step(InputState(), map)) return false }
        return true
    }

    @Test fun fallDamage() {
        assertTrue(survivesFall(6))
        assertFalse(survivesFall(7))
    }

    @Test fun wallClimbInLevel2() {
        val map = LevelMap(Levels.all[1])
        val p = Player(map.spawns.first { it.kind == 'P' }.center)
        var maxY = p.pos.y
        for (f in 0 until 2400) {
            if (p.step(InputState(1, f % 30 < 27, f % 30 == 0), map)) break
            maxY = maxOf(maxY, p.pos.y)
        }
        assertTrue("climbed to row ${maxY / TS}", maxY / TS > 21f)
    }
}
