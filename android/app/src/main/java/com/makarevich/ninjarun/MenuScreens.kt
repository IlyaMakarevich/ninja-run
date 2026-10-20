package com.makarevich.ninjarun

import android.graphics.Canvas
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.random.Random

class MenuScreen(view: GameView) : Screen(view) {
    private val play = Button(L.play, 220f, 54f, 24f, Theme.accent) { go(LevelSelectScreen(view)) }
    private val soundButton = Button("", 160f, 38f, 16f) {
        Sound.enabled = !Sound.enabled
        updateSoundLabel()
    }
    private val langButton = Button("${L.language}: ${Lang.current.nativeName}", 200f, 38f, 16f) { showPicker() }
    private var picker: List<Button>? = null

    // Trick show: the ninja runs, hops and flips on its own.
    private enum class Trick { HOP, FRONT_FLIP, BACK_FLIP, DOUBLE_FLIP, SPIN }
    private val scale = 2.2f
    private val gravity = 0.42f
    private var nx = 60f
    private var vx = 3f
    private var phase = 0f
    private var t = 0f
    private var height = 0f
    private var vy = 0f
    private var airFrames = 0f
    private var airTotal = 1f
    private var turns = 0f
    private var spinning = false
    private var nextTrick = 70
    private var groundY = 0f
    private var accumulator = 0f
    private val fx = mutableListOf<Fx>()

    init { updateSoundLabel() }

    private fun updateSoundLabel() {
        soundButton.text = if (Sound.enabled) L.soundOn else L.soundOff
    }

    override fun activeButtons() = picker ?: listOf(play, soundButton, langButton)

    override fun layout() {
        play.cx = w / 2; play.cy = h * 0.50f
        soundButton.cx = w / 2 - 92; soundButton.cy = h * 0.50f + 54
        langButton.cx = w / 2 + 112; langButton.cy = h * 0.50f + 54
        groundY = h - (insets.bottom + 40)
        picker?.let { layoutPicker(it) }
    }

    // region Language picker

    private val pickerCols = 4
    private val cellW = 150f
    private val cellH = 44f
    private val gap = 12f
    private val gridW get() = pickerCols * cellW + (pickerCols - 1) * gap
    private val pickerScale get() = min(1f, (w - insets.left - insets.right - 24) / (gridW + 40))

    private fun showPicker() {
        picker = Lang.entries.map { lang ->
            Button(lang.nativeName, cellW, cellH, 17f, if (lang == Lang.current) Theme.accent else Theme.button) {
                Lang.current = lang
                go(MenuScreen(view), fade = false)
            }
        }.also { layoutPicker(it) }
    }

    private fun layoutPicker(buttons: List<Button>) {
        val sc = pickerScale
        buttons.forEachIndexed { i, b ->
            val row = i / pickerCols
            val col = i % pickerCols
            val inRow = if (row == 0) pickerCols else buttons.size - pickerCols
            val rowW = inRow * cellW + (inRow - 1) * gap
            b.scale = sc
            b.cx = w / 2 + (-rowW / 2 + cellW / 2 + col * (cellW + gap)) * sc
            b.cy = h / 2 + (-10 + row * (cellH + gap)) * sc
        }
    }

    override fun onFreeTouchDown(id: Int, x: Float, y: Float) {
        picker = null   // tapping outside the language buttons closes the picker
    }

    override fun onBack(): Boolean {
        if (picker != null) { picker = null; return true }
        return false
    }

    // endregion

    // region Ninja tricks

    override fun update(dt: Float) {
        accumulator += dt
        var steps = 0
        while (accumulator >= 1f / 60 && steps < 5) {
            step()
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

    private fun step() {
        t += 1f / 60
        val airborne = height > 0 || vy > 0
        nx += vx
        // At the screen edge: either a wall kick with a back flip or a quick turn.
        if ((nx > w - 40 && vx > 0) || (nx < 40 && vx < 0)) {
            vx = -vx
            if (!airborne && Random.nextBoolean()) jump(7.5f, -1f)
        }
        if (airborne) {
            vy -= gravity
            height += vy
            airFrames += 1
            if (height <= 0) land()
        } else {
            phase += kotlin.math.abs(vx) * 0.22f
            nextTrick--
            if (nextTrick <= 0) startRandomTrick()
        }
    }

    private fun startRandomTrick() {
        when (Trick.entries.random()) {
            Trick.HOP -> jump(5f, 0f)
            Trick.FRONT_FLIP -> jump(7.5f, 1f)
            Trick.BACK_FLIP -> jump(7.5f, -1f)
            Trick.DOUBLE_FLIP -> jump(9.5f, 2f)
            Trick.SPIN -> jump(7f, 0f, spin = true)
        }
        nextTrick = Random.nextInt(45, 131)
    }

    private fun jump(v: Float, turns: Float, spin: Boolean = false) {
        vy = v
        height = 0.01f
        airFrames = 0f
        airTotal = 2 * v / gravity
        this.turns = turns
        spinning = spin
        dust()
    }

    private fun land() {
        height = 0f
        vy = 0f
        turns = 0f
        spinning = false
        dust()
    }

    private fun dust() {
        val x0 = nx
        for (i in 0 until 5) {
            val o = (i - 2).toFloat()
            fx.add(Fx(0.35f) { c, k ->
                c.drawCircle(x0 + o * 6 + o * 10 * k, groundY - 3 - 6 * k, 3f, P.fill(Theme.rgb(0x6B7280), 0.6f * (1 - k)))
            })
        }
    }

    // endregion

    override fun draw(c: Canvas) {
        c.drawColor(Theme.levelBG)
        Txt.draw(c, "NINJA RUN", w / 2, h * 0.24f, 64f, Theme.ninja, Theme.logoFont)
        Txt.draw(c, L.subtitle, w / 2, h * 0.24f + 48, 16f, Theme.text)
        play.draw(c)
        soundButton.draw(c)
        langButton.draw(c)

        P.rect.set(0f, groundY, w, h)
        c.drawRect(P.rect, P.fill(Theme.tile))
        for (f in fx) f.draw(c, clampf(f.age / f.duration, 0f, 1f))

        // Ninja: y-up local space, scaled up, rotated during flips.
        val facing = if (vx > 0) 1f else -1f
        val k = min(airFrames / airTotal, 1f)
        val eased = k * k * (3 - 2 * k)
        val rot = if (height > 0) -facing * turns * 2 * PI.toFloat() * eased else 0f
        val spinFacing = if (spinning && height > 0) (if ((airFrames / 5).toInt() % 2 == 0) facing else -facing) else facing
        c.save()
        c.translate(nx, groundY - 10 * scale - height)
        c.scale(scale, -scale)
        c.rotate(deg(rot))
        NinjaArt.draw(c, Vec(vx, if (height > 0) vy / scale * 2 else 0f), height <= 0, false, 0,
            spinFacing, phase, t)
        c.restore()

        picker?.let { buttons ->
            c.drawColor(P.withAlpha(Theme.rgb(0x000000), 0.45f))
            val sc = pickerScale
            c.save()
            c.translate(w / 2, h / 2)
            c.scale(sc, sc)
            P.roundRect(c, 0f, 0f, gridW + 40, 190f, 18f, Theme.levelBG)
            Txt.draw(c, L.language, 0f, -60f, 24f, Theme.text, Theme.titleFont)
            c.restore()
            for (b in buttons) b.draw(c)
        }
    }
}

class LevelSelectScreen(view: GameView) : Screen(view) {
    private val back = Button(L.back, 110f, 36f, 16f) { go(MenuScreen(view)) }
    private val cells: List<Button>
    private val cols = 4
    private val cellW = 150f
    private val cellH = 74f
    private val gap = 14f

    init {
        val unlocked = Progress.unlocked
        cells = Levels.all.indices.map { i ->
            val open = i < unlocked
            val best = Progress.best(i)
            val color = if (best != null) Theme.accent else if (open) Theme.button else Theme.switchOff
            Button("${i + 1}", cellW, cellH, 24f, color, typeface = Theme.titleFont) {
                if (open) go(GameScreen(view, i))
            }.apply {
                enabled = open
                labelOffsetY = -12f
                val name = L.levelNames[i]
                val bestText = best?.let { String.format("★ %.1f", it) }
                val a = if (open) 1f else 0.45f
                decorate = { c ->
                    Txt.draw(c, name, 0f, 10f, 12f, P.withAlpha(Theme.lightText, a))
                    bestText?.let { Txt.draw(c, it, 0f, 26f, 11f, P.withAlpha(Theme.lightText, a), Theme.monoFont) }
                }
            }
        }
    }

    override fun activeButtons() = cells + back

    override fun layout() {
        val topY = insets.top + 34
        back.cx = max(insets.left, 16f) + 65
        back.cy = topY
        val rows = (cells.size + cols - 1) / cols
        val gridW = cols * cellW + (cols - 1) * gap
        val gridH = rows * cellH + (rows - 1) * gap
        val availW = w - insets.left - insets.right - 32
        val availH = h - topY - 30 - insets.bottom - 12
        val sc = minOf(1f, availW / gridW, availH / gridH)
        val originX = w / 2 - gridW * sc / 2 + cellW * sc / 2
        val centerY = (topY + 30 + h - insets.bottom - 12) / 2
        val originY = centerY - gridH * sc / 2 + cellH * sc / 2
        cells.forEachIndexed { i, b ->
            b.scale = sc
            b.cx = originX + (i % cols) * (cellW + gap) * sc
            b.cy = originY + (i / cols) * (cellH + gap) * sc
        }
    }

    override fun onBack(): Boolean {
        go(MenuScreen(view))
        return true
    }

    override fun draw(c: Canvas) {
        c.drawColor(Theme.levelBG)
        Txt.draw(c, L.levels, w / 2, insets.top + 34, 30f, Theme.ninja, Theme.titleFont)
        back.draw(c)
        for (b in cells) b.draw(c)
    }
}
