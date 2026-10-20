package com.makarevich.ninjarun

import android.graphics.Path
import kotlin.math.floor
import kotlin.math.hypot

/** Tile size in world units and level dimensions (in tiles). */
const val TS = 24f
const val COLS = 31
const val ROWS = 23

/** Immutable 2D vector. World space is y-up, like the iOS version. */
data class Vec(val x: Float, val y: Float) {
    operator fun plus(o: Vec) = Vec(x + o.x, y + o.y)
    operator fun minus(o: Vec) = Vec(x - o.x, y - o.y)
    operator fun times(s: Float) = Vec(x * s, y * s)
    val length: Float get() = hypot(x, y)
    fun dot(o: Vec) = x * o.x + y * o.y
    val normalized: Vec
        get() {
            val l = length
            return if (l > 1e-9f) Vec(x / l, y / l) else ZERO
        }
    fun distance(o: Vec) = (this - o).length

    companion object {
        val ZERO = Vec(0f, 0f)
    }
}

fun clampf(v: Float, lo: Float, hi: Float) = if (v < lo) lo else if (v > hi) hi else v

fun distanceToSegment(p: Vec, a: Vec, b: Vec): Float {
    val ab = b - a
    val len2 = ab.dot(ab)
    if (len2 < 1e-9f) return p.distance(a)
    val t = clampf((p - a).dot(ab) / len2, 0f, 1f)
    return p.distance(a + ab * t)
}

private val SQUARE = listOf(Vec(0f, 0f), Vec(1f, 0f), Vec(1f, 1f), Vec(0f, 1f))

/** Tiles with their convex polygon in unit coordinates (counter-clockwise, y-up). */
enum class Tile(val unitPolygon: List<Vec>?) {
    EMPTY(null),
    FULL(SQUARE),
    SLOPE_UP(listOf(Vec(0f, 0f), Vec(1f, 0f), Vec(1f, 1f))),     // '/'
    SLOPE_DOWN(listOf(Vec(0f, 0f), Vec(1f, 0f), Vec(0f, 1f))),   // '\'
    CEIL_RIGHT(listOf(Vec(1f, 0f), Vec(1f, 1f), Vec(0f, 1f))),   // '7'
    CEIL_LEFT(listOf(Vec(0f, 0f), Vec(1f, 1f), Vec(0f, 1f))),    // 'p'
    DOOR(SQUARE);                                                // 'D'

    companion object {
        fun of(c: Char) = when (c) {
            '#' -> FULL
            '/' -> SLOPE_UP
            '\\' -> SLOPE_DOWN
            '7' -> CEIL_RIGHT
            'p' -> CEIL_LEFT
            'D' -> DOOR
            else -> EMPTY
        }
    }
}

/** Closest point on the boundary of a CCW convex polygon, and whether [p] is inside. */
fun closestOnPolygon(poly: List<Vec>, p: Vec): Pair<Vec, Boolean> {
    var inside = true
    var best = Vec.ZERO
    var bestD = Float.MAX_VALUE
    for (i in poly.indices) {
        val a = poly[i]
        val b = poly[(i + 1) % poly.size]
        val ab = b - a
        if (ab.x * (p.y - a.y) - ab.y * (p.x - a.x) < 0) inside = false
        val t = clampf((p - a).dot(ab) / ab.dot(ab), 0f, 1f)
        val q = a + ab * t
        val d = q.distance(p)
        if (d < bestD) {
            bestD = d; best = q
        }
    }
    return best to inside
}

class Spawn(val kind: Char, val col: Int, val row: Int) {   // row counted from the bottom
    val center get() = Vec((col + 0.5f) * TS, (row + 0.5f) * TS)
}

class LevelMap(map: String) {
    val tiles = Array(ROWS) { Array(COLS) { Tile.EMPTY } }   // [row from bottom][col]
    var doorsOpen = false
    val spawns = mutableListOf<Spawn>()

    init {
        val lines = map.lines().filter { it.isNotBlank() }
        for (r in 0 until ROWS) {
            val line = lines.getOrElse(r) { "" }
            val y = ROWS - 1 - r
            for (x in 0 until COLS) {
                val ch = line.getOrElse(x) { '.' }
                val tile = Tile.of(ch)
                tiles[y][x] = tile
                if (tile == Tile.EMPTY && ch != '.' && ch != ' ') spawns.add(Spawn(ch, x, y))
            }
        }
    }

    val worldW get() = COLS * TS
    val worldH get() = ROWS * TS

    /** Tile at a grid cell; anything outside the level is solid. */
    fun tile(x: Int, y: Int): Tile {
        if (x < 0 || x >= COLS || y < 0 || y >= ROWS) return Tile.FULL
        val t = tiles[y][x]
        return if (t == Tile.DOOR && doorsOpen) Tile.EMPTY else t
    }

    fun cellX(p: Vec) = floor(p.x / TS).toInt()
    fun cellY(p: Vec) = floor(p.y / TS).toInt()
    fun isOpenCell(x: Int, y: Int) = tile(x, y) == Tile.EMPTY

    fun polygon(x: Int, y: Int): List<Vec>? {
        val unit = tile(x, y).unitPolygon ?: return null
        return unit.map { Vec(x * TS + it.x * TS, y * TS + it.y * TS) }
    }

    fun isSolid(p: Vec): Boolean {
        val poly = polygon(cellX(p), cellY(p)) ?: return false
        return closestOnPolygon(poly, p).second
    }

    /** Pushes a circle out of the geometry. Returns the new center and contact normals (pointing away from walls). */
    fun collideCircle(center: Vec, r: Float): Pair<Vec, List<Vec>> {
        var c = center
        val normals = mutableListOf<Vec>()
        repeat(3) {
            var moved = false
            val x0 = floor((c.x - r) / TS).toInt()
            val x1 = floor((c.x + r) / TS).toInt()
            val y0 = floor((c.y - r) / TS).toInt()
            val y1 = floor((c.y + r) / TS).toInt()
            for (ty in y0..y1) for (tx in x0..x1) {
                val poly = polygon(tx, ty) ?: continue
                val (cp, inside) = closestOnPolygon(poly, c)
                val d = c - cp
                val dist = d.length
                if (dist <= 1e-6f) continue
                val n: Vec
                val push: Float
                if (inside) {
                    n = d * (-1f / dist); push = r + dist
                } else {
                    if (dist >= r) continue
                    n = d * (1f / dist); push = r - dist
                }
                c += n * push
                normals.add(n)
                moved = true
            }
            if (!moved) return c to normals
        }
        return c to normals
    }

    /** Distance along [dir] (normalized) until geometry is hit, capped at [maxDist]. */
    fun raycast(from: Vec, dir: Vec, maxDist: Float): Float {
        var t = 0f
        while (t < maxDist) {
            if (isSolid(from + dir * t)) return t
            t += 2f
        }
        return maxDist
    }

    fun lineOfSight(a: Vec, b: Vec): Boolean {
        val d = b - a
        val len = d.length
        return raycast(a, d.normalized, len) >= len
    }

    /** One combined path (world coordinates, y-up) for all static solid tiles. */
    fun staticTilesPath(): Path {
        val path = Path()
        for (y in 0 until ROWS) for (x in 0 until COLS) {
            if (tiles[y][x] == Tile.DOOR) continue
            val poly = polygon(x, y) ?: continue
            path.moveTo(poly[0].x, poly[0].y)
            for (i in 1 until poly.size) path.lineTo(poly[i].x, poly[i].y)
            path.close()
        }
        return path
    }
}
