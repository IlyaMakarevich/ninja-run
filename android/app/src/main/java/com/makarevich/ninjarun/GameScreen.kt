package com.makarevich.ninjarun

import android.graphics.Canvas
import android.graphics.Paint
import android.text.StaticLayout
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

class GameScreen(view: GameView, val index: Int) : Screen(view) {
    enum class State { READY, PLAYING, DEAD, WON, PAUSED }

    val map = LevelMap(Levels.all[index])
    val player: Player
    var state = State.READY
        private set
    var time = 0f          // seconds, drives idle animations
        private set
    var frame = 0          // fixed simulation frames
        private set

    private val entities = mutableListOf<Entity>()
    private var exitDoor: ExitDoor? = null
    private val doorCells = mutableListOf<Pair<Int, Int>>()
    private var doorsFade = 1f
    private var keysLeft = 0
    private val tilesPath = map.staticTilesPath()

    private val startTime = 90f
    private var timeLeft = 90f
    private var goldCount = 0
    private var goldTotal = 0
    private var deadFrames = 0
    private var stateBeforePause = State.READY
    private var playerScale = 1f
    private var accumulator = 0f

    private val fx = mutableListOf<Fx>()
    private class Debris(val kind: Int, var pos: Vec, var vel: Vec, var rot: Float, var spin: Float)
    private val debris = mutableListOf<Debris>()

    // HUD
    private val pauseButton = Button("II", 44f, 30f, 15f) { pause() }
    private val restartButton = Button("↻", 44f, 30f, 18f) { restart() }
    private val barWidth = 220f
    private var hint: StaticLayout? = null
    private var hintAlpha = 1f
    private var hintFading = -1f

    // Controls
    private enum class Role { PAD, JUMP }
    private val touchRoles = mutableMapOf<Int, Role>()
    private val padDx = mutableMapOf<Int, Int>()
    private var jumpEdge = false
    private var keyJumpWasDown = false
    private var leftActive = false
    private var rightActive = false
    private var jumpActive = false

    // Layout (dp)
    private var s = 1f
    private var levelX = 0f
    private var levelTop = 0f
    private var padCenter = Vec.ZERO
    private var leftBtn = Vec.ZERO
    private var rightBtn = Vec.ZERO
    private var jumpBtn = Vec.ZERO
    private var hudY = 0f
    private var hudLeft = 0f
    private var hudRight = 0f

    // Overlay (pause / win)
    private class Overlay(val title: String, val subtitle: String?, val buttons: List<Button>) {
        var alpha = 0f
        var scale = 1f
    }
    private var overlay: Overlay? = null
    private var winOverlayIn = -1f

    init {
        val start = map.spawns.firstOrNull { it.kind == 'P' }?.center ?: Vec(48f, 48f)
        player = Player(start)
        for (y in 0 until ROWS) for (x in 0 until COLS) if (map.tiles[y][x] == Tile.DOOR) doorCells.add(x to y)
        for (sp in map.spawns) {
            val c = sp.center
            val e: Entity? = when (sp.kind) {
                'G' -> { goldTotal++; Gold(c) }
                'M' -> Mine(c)
                'S' -> ExitSwitch(c)
                'E' -> ExitDoor(c).also { exitDoor = it }
                'k' -> { keysLeft++; Key(c) }
                '^' -> Launchpad(c)
                'e' -> Drone(c, 1, 0, false, map)
                'w' -> Drone(c, -1, 0, false, map)
                'n' -> Drone(c, 0, 1, false, map)
                's' -> Drone(c, 0, -1, false, map)
                'c' -> Drone(c, 1, 0, true, map)
                'T' -> GaussTurret(c)
                'r' -> RocketTurret(c)
                else -> null
            }
            if (e != null) entities.add(e)
        }
    }

    override fun activeButtons(): List<Button> = overlay?.buttons ?: listOf(pauseButton, restartButton)

    override fun layout() {
        val ins = insets
        val hudH = 36f
        val bottom = ins.bottom + 6
        val availH = h - ins.top - hudH - bottom
        val ww = map.worldW
        val wh = map.worldH
        s = min(availH / wh, (w - ins.left - ins.right - 8) / ww)
        levelX = (w - ww * s) / 2
        levelTop = ins.top + hudH + (availH - wh * s) / 2

        hudY = ins.top + hudH / 2
        hudLeft = max(ins.left, 12f) + 4
        hudRight = w - max(ins.right, 12f) - 4
        pauseButton.cx = hudLeft + 22; pauseButton.cy = hudY
        restartButton.cx = hudRight - 22; restartButton.cy = hudY

        // Controls live in the side margins when there is room, otherwise overlap the level.
        val sideSpace = levelX - ins.left
        val padX = if (sideSpace > 170) ins.left + sideSpace / 2 else hudLeft + 80
        padCenter = Vec(padX, h - bottom - 66)
        leftBtn = Vec(padX - 42, padCenter.y)
        rightBtn = Vec(padX + 42, padCenter.y)
        val rightSpace = w - ins.right - (levelX + ww * s)
        val jx = if (rightSpace > 130) w - ins.right - rightSpace / 2 else hudRight - 60
        jumpBtn = Vec(jx, h - bottom - 70)

        if (hint == null && index < L.hints.size) hint = Txt.layout(L.hints[index], 11f, Theme.text, 400)
        overlay?.let { layoutOverlay(it) }
    }

    // region Game events (called by entities)

    fun addFx(f: Fx) { fx.add(f) }

    fun collectGold() {
        goldCount++
        timeLeft += 2
        Sound.play(SFX.GOLD)
        Haptics.light()
    }

    fun activateExit() {
        exitDoor?.setOpen()
        Sound.play(SFX.SWITCH_ON)
        view.postDelayed({ Sound.play(SFX.DOOR_OPEN) }, 150)
        Haptics.light()
    }

    fun collectKey() {
        keysLeft--
        Sound.play(SFX.KEY)
        if (keysLeft <= 0) map.doorsOpen = true
        Haptics.light()
    }

    fun killPlayer() {
        if (state != State.PLAYING) return
        state = State.DEAD
        deadFrames = 0
        spawnDebris()
        Sound.play(SFX.DEATH)
        Haptics.heavy()
    }

    fun levelComplete() {
        if (state != State.PLAYING) return
        state = State.WON
        Progress.record(index, timeLeft)
        Haptics.success()
        Sound.play(SFX.WIN)
        winOverlayIn = 0.35f
        clearTouches()
    }

    fun explosion(at: Vec, radius: Float) {
        Sound.play(SFX.EXPLOSION)
        fx.add(Fx(0.35f) { c, t ->
            val sc = min(1f, 0.2f + 0.8f * t * 0.35f / 0.18f)
            c.drawCircle(at.x, at.y, radius * sc, P.fill(Theme.rgb(0xFF8A3D), 0.8f * (1 - t)))
            c.drawCircle(at.x, at.y, radius * sc, P.stroke(Theme.mine, 2f, 1 - t))
        })
    }

    fun zap(at: Vec) {
        Sound.play(SFX.ZAP)
        fx.add(zapFx(at))
    }

    // endregion

    // region Loop

    override fun update(dt: Float) {
        // The overlay fades in even while the game itself is paused.
        overlay?.let { it.alpha = min(1f, it.alpha + dt / 0.2f) }
        if (state == State.PAUSED) return
        time += dt
        if (winOverlayIn > 0) {
            winOverlayIn -= dt
            if (winOverlayIn <= 0) showWinOverlay()
        }
        if (state == State.WON) playerScale = max(0f, playerScale - dt / 0.25f)
        if (hintFading >= 0) {
            hintFading += dt
            hintAlpha = if (hintFading < 2.5f) 1f else max(0f, 1 - (hintFading - 2.5f) / 0.6f)
        }
        if (map.doorsOpen && doorsFade > 0) doorsFade = max(0f, doorsFade - dt / 0.3f)

        accumulator += dt
        var steps = 0
        while (accumulator >= 1f / 60 && steps < 5) {
            fixedStep()
            accumulator -= 1f / 60
            steps++
        }
        if (steps == 5) accumulator = 0f
        val it = fx.iterator()
        while (it.hasNext()) {
            val f = it.next()
            f.age += dt
            if (f.age >= f.duration) it.remove()
        }
    }

    private fun fixedStep() {
        frame++
        val inp = readInput()
        when (state) {
            State.READY -> {
                if (inp.dx == 0 && !inp.jumpPressed) return
                state = State.PLAYING
                hintFading = 0f
                stepPlaying(inp)
            }
            State.PLAYING -> stepPlaying(inp)
            State.DEAD -> {
                deadFrames++
                stepDebris()
                for (e in entities.toList()) e.update(this)
                if ((deadFrames > 25 && inp.jumpPressed) || deadFrames > 80) restart()
            }
            State.WON, State.PAUSED -> {}
        }
    }

    private fun stepPlaying(inp: InputState) {
        timeLeft -= 1f / 60
        if (timeLeft <= 0) {
            timeLeft = 0f
            killPlayer()
            return
        }
        if (player.step(inp, map)) {
            killPlayer()
            return
        }
        if (player.didJump) {
            jumpDust()
            Sound.play(if (player.didWallJump) SFX.WALL_JUMP else SFX.JUMP)
        } else if (player.landImpact > 1.2f) {
            Sound.play(SFX.LAND)
        }
        for (e in entities.toList()) {
            e.update(this)
            if (state != State.PLAYING && state != State.DEAD) break
        }
    }

    private fun readInput(): InputState {
        var dx = padDx.values.sum().coerceIn(-1, 1)
        var held = touchRoles.values.contains(Role.JUMP)
        var pressed = jumpEdge
        jumpEdge = false

        val keys = view.keysDown
        if (dx == 0) {
            val l = keys.any { it in GameView.LEFT_KEYS }
            val r = keys.any { it in GameView.RIGHT_KEYS }
            dx = (if (r) 1 else 0) - (if (l) 1 else 0)
        }
        val j = keys.any { it in GameView.JUMP_KEYS }
        if (j && !keyJumpWasDown) pressed = true
        keyJumpWasDown = j
        held = held || j

        leftActive = dx < 0
        rightActive = dx > 0
        jumpActive = held
        return InputState(dx, held, pressed)
    }

    // endregion

    // region Effects

    private fun jumpDust() {
        val base = player.pos + Vec(0f, -player.r)
        for (i in 0 until 4) {
            val o = (i - 2).toFloat()
            fx.add(Fx(0.3f) { c, t ->
                c.drawCircle(base.x + o * 3 + o * 5 * t, base.y + 3 * t, 1.6f, P.fill(Theme.rgb(0x6B7280), 0.7f * (1 - t)))
            })
        }
    }

    private fun spawnDebris() {
        val v0 = player.vel
        for (kind in 0 until 7) {
            val v = v0 * 0.6f + Vec(Random.nextFloat() * 4.4f - 2.2f, 0.5f + Random.nextFloat() * 2.7f)
            val p = player.pos + Vec(Random.nextFloat() * 8 - 4, Random.nextFloat() * 12 - 6)
            debris.add(Debris(kind, p, v, 0f, Random.nextFloat() * 0.6f - 0.3f))
        }
    }

    private fun stepDebris() {
        for (d in debris) {
            var v = Vec(d.vel.x, d.vel.y - 0.12f) * 0.99f
            val next = d.pos + v
            if (map.isSolid(Vec(next.x, d.pos.y))) { v = Vec(-v.x * 0.4f, v.y); d.spin *= 0.5f }
            if (map.isSolid(Vec(d.pos.x, next.y))) { v = Vec(v.x * 0.7f, -v.y * 0.35f); d.spin *= 0.5f }
            d.vel = v
            d.pos += v
            d.rot += d.spin
        }
    }

    // endregion

    // region Drawing

    override fun draw(c: Canvas) {
        c.drawColor(Theme.screen)

        // World (y-up).
        c.save()
        c.translate(levelX, levelTop + map.worldH * s)
        c.scale(s, -s)
        P.rect.set(0f, 0f, map.worldW, map.worldH)
        c.drawRect(P.rect, P.fill(Theme.levelBG))
        c.drawPath(tilesPath, P.fill(Theme.tile))
        if (doorsFade > 0) for ((x, y) in doorCells) {
            P.rect.set(x * TS + 3, y * TS, x * TS + TS - 3, y * TS + TS)
            c.drawRect(P.rect, P.fill(Theme.wood, doorsFade))
            c.drawRect(P.rect, P.stroke(Theme.ninja, 1f, doorsFade))
        }
        for (e in entities) e.draw(c, this)
        if (state != State.DEAD && playerScale > 0) {
            c.save()
            c.translate(player.pos.x, player.pos.y)
            c.scale(playerScale, playerScale)
            NinjaArt.draw(c, player.vel, player.grounded, player.wallSliding, player.wallSide,
                player.facing, player.runPhase, frame / 60f)
            c.restore()
        }
        for (f in fx) f.draw(c, clampf(f.age / f.duration, 0f, 1f))
        drawDebris(c)
        c.restore()

        // Hint over the top of the level.
        hint?.let {
            if (hintAlpha > 0) {
                c.save()
                c.translate(levelX + map.worldW * s / 2 - it.width / 2f, levelTop + TS * 0.9f * s)
                it.paint.alpha = (hintAlpha * 255).toInt()
                it.draw(c)
                c.restore()
            }
        }

        drawHUD(c)
        drawControls(c)
        overlay?.let { drawOverlay(c, it) }
    }

    private fun drawDebris(c: Canvas) {
        for (d in debris) {
            c.save()
            c.translate(d.pos.x, d.pos.y)
            c.rotate(deg(d.rot))
            when (d.kind) {
                0 -> c.drawLine(0f, -4f, 0f, 4f, P.stroke(Theme.ninja, 2f))
                in 1..4 -> c.drawLine(-3f, -4f, 3f, 4f, P.stroke(Theme.ninja, 2f))
                5 -> c.drawCircle(0f, 0f, 3.6f, P.fill(Theme.ninja))
                else -> { P.rect.set(-3.5f, -0.8f, 3.5f, 0.8f); c.drawRect(P.rect, P.fill(Theme.scarf)) }
            }
            c.restore()
        }
    }

    private fun drawHUD(c: Canvas) {
        pauseButton.draw(c)
        restartButton.draw(c)
        Txt.draw(c, "${index + 1}. ${L.levelNames[index]}", hudLeft + 54, hudY, 15f, Theme.lightText, Theme.uiFont, Paint.Align.LEFT)
        val barX = w / 2 - barWidth / 2 + 40
        P.roundRect(c, barX + barWidth / 2, hudY, barWidth, 10f, 5f, Theme.rgb(0x000000, 0.25f))
        val frac = clampf(timeLeft / startTime, 0f, 1f)
        if (frac > 0) {
            P.rect.set(barX, hudY - 5, barX + barWidth * frac, hudY + 5)
            val r = min(5f, barWidth * frac / 2)
            c.drawRoundRect(P.rect, r, r, P.fill(if (timeLeft < 15) Theme.mine else Theme.gold))
        }
        Txt.draw(c, String.format("%5.1f", timeLeft), w / 2 - barWidth / 2 + 4, hudY, 14f, Theme.lightText, Theme.monoFont)
        Txt.draw(c, "■ $goldCount/$goldTotal", hudRight - 56, hudY, 14f, Theme.gold, Theme.monoFont, Paint.Align.RIGHT)
    }

    private fun drawControls(c: Canvas) {
        fun control(at: Vec, r: Float, active: Boolean, angleDeg: Float) {
            c.drawCircle(at.x, at.y, r, P.fill(Theme.rgb(0xFFFFFF), if (active) 0.45f else 0.18f))
            c.drawCircle(at.x, at.y, r, P.stroke(Theme.rgb(0xFFFFFF), 2f, 0.45f))
            val a = r * 0.32f
            c.save()
            c.translate(at.x, at.y)
            c.rotate(angleDeg)
            P.path.reset()
            P.path.moveTo(a, 0f); P.path.lineTo(-a * 0.6f, a); P.path.lineTo(-a * 0.6f, -a); P.path.close()
            c.drawPath(P.path, P.fill(Theme.rgb(0xFFFFFF), 0.85f))
            c.restore()
        }
        control(leftBtn, 34f, leftActive, 180f)
        control(rightBtn, 34f, rightActive, 0f)
        control(jumpBtn, 44f, jumpActive, -90f)
    }

    // endregion

    // region Touch controls

    override fun onFreeTouchDown(id: Int, x: Float, y: Float) {
        if (overlay != null) return
        if (x < w / 2) {
            touchRoles[id] = Role.PAD
            padDx[id] = if (x < padCenter.x) -1 else 1
        } else {
            touchRoles[id] = Role.JUMP
            jumpEdge = true
        }
    }

    override fun onFreeTouchMove(id: Int, x: Float, y: Float) {
        if (touchRoles[id] == Role.PAD) padDx[id] = if (x < padCenter.x) -1 else 1
    }

    override fun onFreeTouchUp(id: Int) {
        touchRoles.remove(id)
        padDx.remove(id)
    }

    private fun clearTouches() {
        touchRoles.clear()
        padDx.clear()
        jumpEdge = false
    }

    // endregion

    // region Flow and overlays

    private fun restart() = go(GameScreen(view, index), fade = false)

    private fun goToLevels() = go(LevelSelectScreen(view))

    private fun pause() {
        if (state == State.WON || overlay != null) return
        stateBeforePause = state
        state = State.PAUSED
        clearTouches()
        showPauseMenu()
    }

    private fun showPauseMenu() {
        showOverlay(L.pause, null, listOf(
            L.resume to { resume() },
            L.restart to { restart() },
            (if (Sound.enabled) L.soundOn else L.soundOff) to {
                Sound.enabled = !Sound.enabled
                overlay = null
                showPauseMenu()
                overlay?.alpha = 1f
            },
            L.levels to { goToLevels() },
        ))
    }

    private fun resume() {
        overlay = null
        state = stateBeforePause
    }

    override fun onAppPause() {
        if (state == State.PLAYING || state == State.READY) pause()
    }

    override fun onBack(): Boolean {
        val o = overlay
        when {
            o == null && state != State.WON -> pause()
            state == State.PAUSED -> resume()
            else -> goToLevels()
        }
        return true
    }

    private fun showWinOverlay() {
        val best = Progress.best(index) ?: timeLeft
        val sub = String.format(L.winStats, timeLeft, best, goldCount, goldTotal)
        val buttons = mutableListOf<Pair<String, () -> Unit>>()
        if (index + 1 < Levels.all.size) buttons.add(L.next to { go(GameScreen(view, index + 1)) })
        buttons.add(L.again to { restart() })
        buttons.add(L.levels to { goToLevels() })
        showOverlay(if (index + 1 < Levels.all.size) L.levelComplete else L.gameComplete, sub, buttons)
    }

    private fun showOverlay(title: String, subtitle: String?, items: List<Pair<String, () -> Unit>>) {
        val buttons = items.mapIndexed { i, (text, action) ->
            Button(text, 240f, 42f, 18f, if (i == 0) Theme.accent else Theme.button, action = action)
        }
        overlay = Overlay(title, subtitle, buttons).also { layoutOverlay(it) }
    }

    private fun panelHeight(o: Overlay) = 120f + o.buttons.size * 52f

    private fun layoutOverlay(o: Overlay) {
        val ph = panelHeight(o)
        o.scale = min(1f, (h - insets.top - insets.bottom - 20) / ph)
        o.buttons.forEachIndexed { i, b ->
            b.scale = o.scale
            b.cx = w / 2
            b.cy = h / 2 + (-ph / 2 + 112 + i * 52) * o.scale
        }
    }

    private fun drawOverlay(c: Canvas, o: Overlay) {
        val a = o.alpha
        c.drawColor(P.withAlpha(Theme.rgb(0x000000), 0.45f * a))
        val ph = panelHeight(o)
        c.save()
        c.translate(w / 2, h / 2)
        c.scale(o.scale, o.scale)
        P.roundRect(c, 0f, 0f, 380f, ph, 18f, Theme.levelBG, alpha = a)
        Txt.draw(c, o.title, 0f, -ph / 2 + 36, 28f, P.withAlpha(Theme.text, a), Theme.titleFont)
        o.subtitle?.let { Txt.draw(c, it, 0f, -ph / 2 + 66, 13f, P.withAlpha(Theme.text, a)) }
        c.restore()
        for (b in o.buttons) { b.alpha = a; b.draw(c) }
    }

    // endregion
}
