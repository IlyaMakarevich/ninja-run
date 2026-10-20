package com.makarevich.ninjarun

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

data class InputState(val dx: Int = 0, val jumpHeld: Boolean = false, val jumpPressed: Boolean = false)

/** Ninja physics. Units are world points per 1/60 s frame (identical to the iOS version). */
class Player(spawn: Vec) {
    object Tuning {
        const val RADIUS = 10f
        const val GROUND_ACCEL = 0.0667f
        const val AIR_ACCEL = 0.0444f
        const val MAX_RUN_SPEED = 3.333f
        const val GRAVITY_FALL = 0.0667f
        const val GRAVITY_JUMP = 0.0111f
        const val MAX_JUMP_FRAMES = 45
        const val DRAG = 0.9933f
        const val GROUND_FRICTION = 0.9459f
        const val WALL_FRICTION = 0.9113f
        const val JUMP_SPEED = 2f
        const val MAX_SURVIVABLE_IMPACT = 6f
        const val SUBSTEPS = 4
        const val MAX_FALL_SPEED = 10f
    }

    val r = Tuning.RADIUS
    var pos = Vec(spawn.x, spawn.y - TS / 2 + r + 0.5f)
    var vel = Vec.ZERO

    var grounded = false; private set
    private var groundNormal = Vec(0f, 1f)
    var wallSide = 0; private set          // -1 wall on the left, 1 on the right
    var wallSliding = false; private set
    var facing = 1f; private set
    var runPhase = 0f; private set
    private var coyote = 0
    private var jumpBuffer = 0
    private var jumping = false
    private var jumpFrames = 0

    var didJump = false; private set
    var didWallJump = false; private set
    /** Impact speed of a landing this frame (0 if none). */
    var landImpact = 0f; private set

    fun launch(vy: Float) {
        vel = Vec(vel.x, vy)
        jumping = false
        grounded = false
        coyote = 0
    }

    /** Advances one frame. Returns true if the ninja died from an impact. */
    fun step(inp: InputState, map: LevelMap): Boolean {
        val t = Tuning
        val ix = inp.dx.toFloat()
        didJump = false
        didWallJump = false
        landImpact = 0f

        if (inp.jumpPressed) jumpBuffer = 6 else if (jumpBuffer > 0) jumpBuffer--

        val probe = r + 3
        val wallL = map.isSolid(Vec(pos.x - probe, pos.y)) || map.isSolid(Vec(pos.x - probe, pos.y - 6))
        val wallR = map.isSolid(Vec(pos.x + probe, pos.y)) || map.isSolid(Vec(pos.x + probe, pos.y - 6))
        wallSide = when {
            grounded -> 0
            wallL && wallR -> if (ix != 0f) ix.toInt() else 1
            wallR -> 1
            wallL -> -1
            else -> 0
        }

        var vx = vel.x
        var vy = vel.y

        // Horizontal control.
        if (ix != 0f) {
            val acc = if (grounded) t.GROUND_ACCEL else t.AIR_ACCEL
            val nv = vx + ix * acc
            if (abs(nv) <= t.MAX_RUN_SPEED || nv * ix < 0) vx = nv
            else if (abs(vx) < t.MAX_RUN_SPEED) vx = ix * t.MAX_RUN_SPEED
            if (grounded && vx * ix < 0) vx *= t.GROUND_FRICTION
            facing = ix
        } else if (grounded) {
            vx *= t.GROUND_FRICTION
            vy *= t.GROUND_FRICTION
        }

        // Jumping.
        if (jumpBuffer > 0) {
            if (grounded || coyote > 0) {
                vy = t.JUMP_SPEED
                if (abs(groundNormal.x) > 0.1f) vx += groundNormal.x * 0.7f
                startJump()
            } else if (wallSide != 0) {
                val away = -wallSide.toFloat()
                if (ix == wallSide.toFloat()) {
                    vx = away * 2f / 3f; vy = 1f
                } else {
                    vx = away; vy = 1.4f
                }
                facing = away
                startJump()
                didWallJump = true
            }
        }

        // Gravity: lighter while the jump button is held during a jump.
        val holding = jumping && inp.jumpHeld && jumpFrames < t.MAX_JUMP_FRAMES && vy > 0
        if (!holding) jumping = false
        vy -= if (holding) t.GRAVITY_JUMP else t.GRAVITY_FALL
        jumpFrames++

        // Wall sliding.
        wallSliding = false
        if (!grounded && wallSide != 0 && ix == wallSide.toFloat() && vy < 0) {
            vy *= t.WALL_FRICTION
            wallSliding = true
        }

        if (!grounded) vx *= t.DRAG
        vy = max(vy, -t.MAX_FALL_SPEED)
        vel = Vec(vx, vy)

        // Integrate with substeps and resolve collisions.
        var nowGrounded = false
        var floorImpact = 0f
        var died = false
        val inv = 1f / t.SUBSTEPS
        repeat(t.SUBSTEPS) {
            val (np, normals) = map.collideCircle(pos + vel * inv, r)
            pos = np
            for (n in normals) {
                val vn = vel.dot(n)
                if (n.y > 0.5f) floorImpact = max(floorImpact, -vn)
                if (vn < 0) {
                    val impact = -vn
                    val limit = t.MAX_SURVIVABLE_IMPACT - 4f / 3f * abs(n.y)
                    if (abs(n.y) > 0.1f && impact > limit) died = true
                    vel = vel - n * vn
                }
                if (n.y > 0.5f) {
                    nowGrounded = true
                    groundNormal = n
                }
            }
        }

        if (nowGrounded) {
            if (!grounded) landImpact = floorImpact
            grounded = true
            coyote = 5
        } else {
            if (grounded) coyote = 5
            grounded = false
            if (coyote > 0) coyote--
        }
        if (grounded) runPhase += abs(vel.x) * 0.22f
        return died
    }

    private fun startJump() {
        jumping = true
        jumpFrames = 0
        jumpBuffer = 0
        coyote = 0
        grounded = false
        didJump = true
    }
}

/**
 * Procedurally drawn stick-figure ninja. Draws around the origin in a y-up coordinate
 * system (the caller sets up the canvas), facing right before [facing] is applied.
 */
object NinjaArt {
    private val body = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE; strokeWidth = 2f; strokeCap = Paint.Cap.ROUND
        strokeJoin = Paint.Join.ROUND; color = Theme.ninja
    }
    private val scarf = Paint(body).apply { strokeWidth = 1.6f; color = Theme.scarf }
    private val head = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Theme.ninja }
    private val path = Path()

    fun draw(
        c: Canvas, vel: Vec, grounded: Boolean, wallSliding: Boolean, wallSide: Int,
        facing: Float, phase: Float, time: Float,
    ) {
        val speed = abs(vel.x)
        var lean = 0f
        val feet: Pair<Vec, Vec>
        val knees: Pair<Vec, Vec>
        val hands: Pair<Vec, Vec>
        var dir = facing
        val hip = Vec(0f, -2f)

        if (wallSliding) {
            dir = wallSide.toFloat()
            lean = -1.5f
            feet = Vec(5f, -9f) to Vec(2f, -10f)
            knees = Vec(1f, -5f) to Vec(-1f, -6f)
            hands = Vec(6f, 6f) to Vec(6f, 2f)
        } else if (grounded) {
            if (speed > 0.15f) {
                lean = min(speed, 3.3f) * 0.7f
                val s = sin(phase)
                val co = cos(phase)
                val stride = min(speed * 2.2f, 6.5f)
                feet = Vec(s * stride, -10 + max(0f, co) * 3) to Vec(-s * stride, -10 + max(0f, -co) * 3)
                knees = Vec(s * stride * 0.5f + 2, -6 + max(0f, co) * 1.5f) to
                    Vec(-s * stride * 0.5f + 2, -6 + max(0f, -co) * 1.5f)
                hands = Vec(-s * 5 + lean, -1f) to Vec(s * 5 + lean, -1f)
            } else {
                feet = Vec(3f, -10f) to Vec(-3f, -10f)
                knees = Vec(2f, -6f) to Vec(-2f, -6f)
                hands = Vec(3f, -4f) to Vec(-3f, -4f)
            }
        } else if (vel.y > 0) {
            lean = clampf(speed * 0.5f, 0f, 1.5f)
            feet = Vec(3f, -7f) to Vec(-2f, -9f)
            knees = Vec(4f, -3f) to Vec(0f, -6f)
            hands = Vec(4f, 7f) to Vec(-3f, 6f)
        } else {
            lean = clampf(speed * 0.4f, 0f, 1.2f)
            feet = Vec(3f, -10f) to Vec(-3f, -9f)
            knees = Vec(2f, -6f) to Vec(-2f, -6f)
            hands = Vec(6f, 3f) to Vec(-6f, 4f)
        }

        c.save()
        c.scale(dir, 1f)
        val neck = Vec(lean, 4f)
        val shoulder = Vec(lean * 0.9f, 3f)
        val headC = neck + Vec(lean * 0.3f, 3.8f)

        // Scarf trails behind and flutters with speed.
        val v = vel.length
        val flutter = sin(time * 18) * (0.6f + min(v, 4f) * 0.4f)
        val trail = 5 + min(v, 4f) * 1.6f
        val knot = headC + Vec(-2.5f, 0.8f)
        path.reset()
        path.moveTo(knot.x, knot.y)
        path.lineTo(knot.x - trail * 0.55f, knot.y + flutter * 0.5f - vel.y * 0.4f)
        path.lineTo(knot.x - trail, knot.y + flutter - vel.y * 0.9f)
        c.drawPath(path, scarf)

        path.reset()
        path.moveTo(hip.x, hip.y); path.lineTo(neck.x, neck.y)
        path.moveTo(hip.x, hip.y); path.lineTo(knees.first.x, knees.first.y); path.lineTo(feet.first.x, feet.first.y)
        path.moveTo(hip.x, hip.y); path.lineTo(knees.second.x, knees.second.y); path.lineTo(feet.second.x, feet.second.y)
        for (h in listOf(hands.first, hands.second)) {
            val elbow = shoulder + (h - shoulder) * 0.5f + Vec(0f, -1f)
            path.moveTo(shoulder.x, shoulder.y); path.lineTo(elbow.x, elbow.y); path.lineTo(h.x, h.y)
        }
        c.drawPath(path, body)
        c.drawCircle(headC.x, headC.y, 3.6f, head)
        c.restore()
    }
}
