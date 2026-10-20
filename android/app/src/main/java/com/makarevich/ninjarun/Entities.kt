package com.makarevich.ninjarun

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/** Shared, reusable paints (all drawing happens on the UI thread). */
object P {
    private val fillP = Paint(Paint.ANTI_ALIAS_FLAG).apply { style = Paint.Style.FILL }
    private val strokeP = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    val rect = RectF()
    val path = Path()

    fun fill(color: Int, alpha: Float = 1f): Paint = fillP.apply { this.color = withAlpha(color, alpha) }
    fun stroke(color: Int, width: Float, alpha: Float = 1f): Paint =
        strokeP.apply { this.color = withAlpha(color, alpha); strokeWidth = width }

    fun withAlpha(color: Int, alpha: Float): Int {
        val a = ((color ushr 24) * clampf(alpha, 0f, 1f)).toInt()
        return (a shl 24) or (color and 0xFFFFFF)
    }

    /** Rounded rect centered at (cx, cy), filled and optionally stroked. */
    fun roundRect(c: Canvas, cx: Float, cy: Float, w: Float, h: Float, r: Float, fill: Int, stroke: Int? = null, sw: Float = 1f, alpha: Float = 1f) {
        rect.set(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
        c.drawRoundRect(rect, r, r, fill(fill, alpha))
        if (stroke != null) c.drawRoundRect(rect, r, r, stroke(stroke, sw, alpha))
    }

    fun line(c: Canvas, a: Vec, b: Vec, paint: Paint) = c.drawLine(a.x, a.y, b.x, b.y, paint)
}

fun deg(rad: Float) = rad * 180f / PI.toFloat()

/** A short-lived visual effect drawn in world space; [draw] gets progress 0…1. */
class Fx(val duration: Float, val draw: (Canvas, Float) -> Unit) {
    var age = 0f
}

/** Base class for everything that lives in a level besides tiles and the ninja. */
abstract class Entity(var pos: Vec) {
    var alive = true
    open fun update(g: GameScreen) {}
    abstract fun draw(c: Canvas, g: GameScreen)

    fun touchesPlayer(g: GameScreen, radius: Float) =
        g.state == GameScreen.State.PLAYING && g.player.pos.distance(pos) < radius + g.player.r
}

// region Pickups and level objects

class Gold(p: Vec) : Entity(p) {
    private val phase = ((p.x + p.y) * 0.05f) % 1f

    override fun update(g: GameScreen) {
        if (!alive || !touchesPlayer(g, 6f)) return
        alive = false
        g.collectGold()
        val at = pos
        g.addFx(Fx(0.2f) { c, t ->
            c.save(); c.translate(at.x, at.y); c.scale(1 + t, 1 + t)
            P.roundRect(c, 0f, 0f, 9f, 9f, 1.5f, Theme.gold, Theme.goldDark, 1.2f, 1 - t)
            c.restore()
        })
    }

    override fun draw(c: Canvas, g: GameScreen) {
        if (!alive) return
        val bob = 0.75f + 0.75f * sin(2 * PI.toFloat() * (g.time / 1.2f + phase))
        P.roundRect(c, pos.x, pos.y + bob, 9f, 9f, 1.5f, Theme.gold, Theme.goldDark, 1.2f)
    }
}

class Mine(p: Vec) : Entity(p) {
    override fun update(g: GameScreen) {
        if (!alive || !touchesPlayer(g, 4f)) return
        alive = false
        g.explosion(pos, 22f)
        g.killPlayer()
    }

    override fun draw(c: Canvas, g: GameScreen) {
        if (!alive) return
        val sp = P.stroke(Theme.ninja, 1.4f)
        for (i in 0 until 8) {
            val a = i * PI.toFloat() / 4
            c.drawLine(pos.x + cos(a) * 3, pos.y + sin(a) * 3, pos.x + cos(a) * 6.5f, pos.y + sin(a) * 6.5f, sp)
        }
        val pulse = 0.8f + 0.2f * cos(2 * PI.toFloat() * g.time)
        c.drawCircle(pos.x, pos.y, 4f, P.fill(Theme.mine, pulse))
        c.drawCircle(pos.x, pos.y, 4f, P.stroke(Theme.ninja, 1.2f))
    }
}

class ExitSwitch(p: Vec) : Entity(p) {
    override fun update(g: GameScreen) {
        if (!alive || !touchesPlayer(g, 7f)) return
        alive = false
        g.activateExit()
    }

    override fun draw(c: Canvas, g: GameScreen) {
        P.roundRect(c, pos.x, pos.y, 12f, 12f, 2f, if (alive) Theme.switchOff else Theme.accent, Theme.ninja, 1.2f)
        val r = if (alive) 3f * (1.2f + 0.2f * sin(2 * PI.toFloat() * g.time / 0.8f)) else 3f
        c.drawCircle(pos.x, pos.y, r, P.fill(if (alive) Theme.accent else Theme.ninja))
    }
}

class ExitDoor(p: Vec) : Entity(p) {
    var open = false; private set
    fun setOpen() { open = true }

    override fun update(g: GameScreen) {
        if (open && touchesPlayer(g, 8f)) g.levelComplete()
    }

    override fun draw(c: Canvas, g: GameScreen) {
        val s = if (open) 1.04f + 0.04f * sin(2 * PI.toFloat() * g.time / 0.7f) else 1f
        c.save(); c.translate(pos.x, pos.y); c.scale(s, s)
        P.rect.set(-10f, -12f, 10f, 12f)
        c.drawRect(P.rect, P.fill(Theme.doorClosed))
        c.drawRect(P.rect, P.stroke(Theme.ninja, 1.5f))
        P.rect.set(-7f, -12f, 7f, 8f)
        c.drawRect(P.rect, P.fill(if (open) Theme.accent else Theme.doorPanel))
        c.restore()
    }
}

class Key(p: Vec) : Entity(p) {
    override fun update(g: GameScreen) {
        if (!alive || !touchesPlayer(g, 7f)) return
        alive = false
        g.collectKey()
        val at = pos
        g.addFx(Fx(0.25f) { c, t ->
            c.save(); c.translate(at.x, at.y); c.scale(1 + t, 1 + t); drawKey(c, 1 - t); c.restore()
        })
    }

    override fun draw(c: Canvas, g: GameScreen) {
        if (!alive) return
        c.save(); c.translate(pos.x, pos.y)
        c.rotate(deg(0.125f + 0.125f * sin(2 * PI.toFloat() * g.time)))
        drawKey(c, 1f)
        c.restore()
    }

    private fun drawKey(c: Canvas, alpha: Float) {
        val p = P.stroke(Theme.key, 2f, alpha)
        c.drawCircle(-4f, 0f, 3f, p)
        c.drawLine(-1f, 0f, 7f, 0f, p)
        c.drawLine(4f, 0f, 4f, -3f, p)
        c.drawLine(6.5f, 0f, 6.5f, -3f, p)
    }
}

class Launchpad(p: Vec) : Entity(p) {
    private var cooldown = 0
    private var squash = 0f
    private val floorY get() = pos.y - TS / 2

    override fun update(g: GameScreen) {
        if (squash > 0) squash -= 1f / 60 / 0.25f
        if (cooldown > 0) { cooldown--; return }
        if (g.state != GameScreen.State.PLAYING) return
        val pl = g.player
        if (abs(pl.pos.x - pos.x) < 14 && pl.pos.y - floorY < pl.r + 8 && pl.pos.y > floorY && pl.vel.y < 4) {
            pl.launch(6f)
            cooldown = 20
            squash = 1f
            Sound.play(SFX.LAUNCHPAD)
            Haptics.light()
        }
    }

    override fun draw(c: Canvas, g: GameScreen) {
        val bob = 1.5f + 1.5f * sin(2 * PI.toFloat() * g.time / 0.8f)
        val ap = P.stroke(Theme.launchpad, 2f)
        val ay = pos.y - 2 + bob
        c.drawLine(pos.x - 4, ay - 4, pos.x, ay, ap)
        c.drawLine(pos.x, ay, pos.x + 4, ay - 4, ap)
        val h = 4f * (1 + 1.5f * clampf(squash, 0f, 1f))
        P.roundRect(c, pos.x, pos.y - TS / 2 + 2, 18f, h, 1f, Theme.launchpad, Theme.ninja, 1f)
    }
}

// endregion

// region Enemies

/**
 * Drone that moves cell to cell. Regular drones bounce back and forth;
 * chasers rush the ninja when they see it along a row or column.
 */
class Drone(p: Vec, private var dx: Int, private var dy: Int, private val chaser: Boolean, map: LevelMap) : Entity(p) {
    private var cx = map.cellX(p)
    private var cy = map.cellY(p)
    private var target = p
    private var chasing = false

    override fun update(g: GameScreen) {
        val speed = if (chasing) 2f else 1f
        val d = target - pos
        if (d.length <= speed) {
            pos = target
            chooseDirection(g)
            if (dx != 0 || dy != 0) {
                cx += dx; cy += dy
                target = Vec((cx + 0.5f) * TS, (cy + 0.5f) * TS)
            }
        } else {
            pos += d.normalized * speed
        }
        if (touchesPlayer(g, 8f)) {
            g.zap(g.player.pos)
            g.killPlayer()
        }
    }

    private fun chooseDirection(g: GameScreen) {
        chasing = false
        if (chaser && g.state == GameScreen.State.PLAYING) {
            sightOfPlayer(g)?.let { (sx, sy) -> dx = sx; dy = sy; chasing = true; return }
        }
        val options = listOf(dx to dy, -dx to -dy, dy to -dx, -dy to dx)
        for ((ox, oy) in options) {
            if ((ox != 0 || oy != 0) && g.map.isOpenCell(cx + ox, cy + oy)) {
                dx = ox; dy = oy; return
            }
        }
        dx = 0; dy = 0
    }

    private fun sightOfPlayer(g: GameScreen): Pair<Int, Int>? {
        val px = g.map.cellX(g.player.pos)
        val py = g.map.cellY(g.player.pos)
        val ddx = px - cx
        val ddy = py - cy
        if ((ddx == 0) == (ddy == 0) || abs(ddx) + abs(ddy) > 12) return null
        val sx = Integer.signum(ddx)
        val sy = Integer.signum(ddy)
        var x = cx
        var y = cy
        while (x != px || y != py) {
            x += sx; y += sy
            if (!g.map.isOpenCell(x, y)) return null
        }
        return sx to sy
    }

    override fun draw(c: Canvas, g: GameScreen) {
        val s = if (chaser) 1.04f + 0.04f * sin(2 * PI.toFloat() * g.time / 0.6f) else 1f
        c.drawCircle(pos.x, pos.y, 9f * s, P.fill(if (chaser) Theme.chaser else Theme.drone))
        c.drawCircle(pos.x, pos.y, 9f * s, P.stroke(Theme.ninja, 1.5f))
        c.drawCircle(pos.x, pos.y, 5.5f, P.fill(Theme.lightText))
        c.drawCircle(pos.x + dx * 2.5f, pos.y + dy * 2.5f, 2.5f, P.fill(Theme.ninja))
    }
}

/**
 * Gauss turret: tracks the ninja with a lagging aim, then freezes the aim
 * (blinking line + beep) for a moment before firing, so a quick step dodges it.
 */
class GaussTurret(p: Vec) : Entity(p) {
    private var aim = Vec.ZERO
    private var charge = 0
    private var cooldown = 0
    private val trackTime = 60      // frames the aim follows the ninja
    private val lockTime = 30       // frames the aim is frozen before the shot
    private val trackSpeed = 1.5f
    private val chargeTime get() = trackTime + lockTime
    private var dir = Vec(0f, -1f)
    private var lineLen = 0f

    override fun update(g: GameScreen) {
        if (cooldown > 0) { cooldown--; lineLen = 0f; return }
        val target = g.player.pos
        val locked = charge >= trackTime
        val canSee = g.state == GameScreen.State.PLAYING && g.map.lineOfSight(pos, target)
        if (charge == 0) {
            if (!canSee) { lineLen = 0f; return }
            aim = target
            Sound.play(SFX.LOCK_ON)
        }
        if (locked) {
            charge++
            if (charge == trackTime + 1) Sound.play(SFX.LOCK_ON)
        } else if (!canSee) {
            charge -= 2
            if (charge <= 0) { charge = 0; lineLen = 0f; return }
        } else {
            charge++
            val d = target - aim
            aim += if (d.length > trackSpeed) d.normalized * trackSpeed else d
        }
        dir = (aim - pos).normalized
        if (charge >= chargeTime) {
            fire(g)
            return
        }
        lineLen = g.map.raycast(pos, dir, 900f)
    }

    private fun fire(g: GameScreen) {
        Sound.play(SFX.GAUSS)
        charge = 0
        cooldown = 90
        lineLen = 0f
        val len = g.map.raycast(pos, dir, 900f)
        val start = pos
        val end = pos + dir * len
        g.addFx(Fx(0.3f) { c, t ->
            P.line(c, start, end, P.stroke(Theme.beam, 7f, 0.3f * (1 - t)))
            P.line(c, start, end, P.stroke(Theme.beam, 3f, 1 - t))
        })
        if (g.state == GameScreen.State.PLAYING && distanceToSegment(g.player.pos, start, end) < g.player.r + 1.5f) {
            g.killPlayer()
        }
    }

    override fun draw(c: Canvas, g: GameScreen) {
        if (lineLen > 0) {
            val end = pos + dir * lineLen
            if (charge >= trackTime) {
                val blinkOn = (charge / 4) % 2 == 0
                if (blinkOn) P.line(c, pos, end, P.stroke(Theme.beam, 7f, 0.3f))
                P.line(c, pos, end, P.stroke(Theme.beam, 3f, if (blinkOn) 1f else 0.25f))
            } else {
                val k = charge.toFloat() / trackTime
                P.line(c, pos, end, P.stroke(Theme.beam, 1 + k, 0.35f + 0.45f * k))
            }
        }
        c.drawCircle(pos.x, pos.y, 7f, P.fill(Theme.turret))
        c.drawCircle(pos.x, pos.y, 7f, P.stroke(Theme.ninja, 1.5f))
        c.save(); c.translate(pos.x + dir.x * 6, pos.y + dir.y * 6); c.rotate(deg(atan2(dir.y, dir.x)))
        P.roundRect(c, 0f, 0f, 10f, 3f, 1f, Theme.ninja)
        c.restore()
        c.drawCircle(pos.x, pos.y, 2.5f, P.fill(Theme.beam))
    }
}

class RocketTurret(p: Vec) : Entity(p) {
    private var rocket: Rocket? = null
    private var cooldown = 60
    private var dir = Vec(-1f, 0f)

    override fun update(g: GameScreen) {
        dir = (g.player.pos - pos).normalized
        rocket?.let {
            it.update(g)
            if (!it.alive) { rocket = null; cooldown = 80 }
            return
        }
        if (cooldown > 0) { cooldown--; return }
        if (g.state == GameScreen.State.PLAYING && g.map.lineOfSight(pos, g.player.pos)) {
            rocket = Rocket(pos + dir * 10f, atan2(dir.y, dir.x))
            Sound.play(SFX.ROCKET)
        }
    }

    override fun draw(c: Canvas, g: GameScreen) {
        P.roundRect(c, pos.x, pos.y, 16f, 16f, 4f, Theme.turret, Theme.ninja, 1.5f)
        c.save(); c.translate(pos.x + dir.x * 6, pos.y + dir.y * 6); c.rotate(deg(atan2(dir.y, dir.x)))
        P.roundRect(c, 0f, 0f, 12f, 5f, 1.5f, Theme.ninja)
        c.restore()
        rocket?.draw(c, g)
    }
}

class Rocket(p: Vec, private var angle: Float) : Entity(p) {
    private var speed = 0.6f
    private var t = 0

    override fun update(g: GameScreen) {
        if (!alive) return
        t++
        val want = atan2(g.player.pos.y - pos.y, g.player.pos.x - pos.x)
        var delta = want - angle
        while (delta > PI) delta -= 2 * PI.toFloat()
        while (delta < -PI) delta += 2 * PI.toFloat()
        if (g.state == GameScreen.State.PLAYING) angle += clampf(delta, -0.04f, 0.04f)
        speed = min(speed + 0.04f, 2.7f)
        val heading = Vec(cos(angle), sin(angle))
        pos += heading * speed

        if (t % 4 == 0) {
            val at = pos - heading * 6f
            g.addFx(Fx(0.5f) { c, k ->
                c.drawCircle(at.x, at.y, 2.5f * (1 + k), P.fill(Theme.rgb(0x9097A3), 0.6f * (1 - k)))
            })
        }
        if (touchesPlayer(g, 4f)) {
            explode(g)
            g.killPlayer()
        } else if (g.map.isSolid(pos) || t > 60 * 12) {
            explode(g)
        }
    }

    private fun explode(g: GameScreen) {
        alive = false
        g.explosion(pos, 18f)
    }

    override fun draw(c: Canvas, g: GameScreen) {
        if (!alive) return
        c.save(); c.translate(pos.x, pos.y); c.rotate(deg(angle))
        val flicker = if ((g.frame / 3) % 2 == 0) 1.5f else 0.8f
        c.drawCircle(-5f, 0f, 2f * flicker, P.fill(Theme.launchpad))
        P.roundRect(c, 0f, 0f, 9f, 4f, 2f, Theme.ninja)
        c.restore()
    }
}

// endregion

/** Lightning bolt effect for drone kills. */
fun zapFx(at: Vec): Fx {
    val pts = mutableListOf(at + Vec(-14f, 10f))
    repeat(6) { pts.add(pts.last() + Vec(5f, Random.nextFloat() * 16 - 8)) }
    return Fx(0.3f) { c, t ->
        for (i in 1 until pts.size) {
            P.line(c, pts[i - 1], pts[i], P.stroke(Theme.rgb(0x7FD3FF), 5f, 0.3f * (1 - t)))
            P.line(c, pts[i - 1], pts[i], P.stroke(Theme.rgb(0x7FD3FF), 2f, 1 - t))
        }
    }
}
