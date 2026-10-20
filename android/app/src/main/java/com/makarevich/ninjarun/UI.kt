package com.makarevich.ninjarun

import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import kotlin.math.abs
import kotlin.math.min

/** Safe-area insets in dp. */
data class Insets(val left: Float = 0f, val top: Float = 0f, val right: Float = 0f, val bottom: Float = 0f)

object Txt {
    private val paint = TextPaint(Paint.ANTI_ALIAS_FLAG)

    fun paint(size: Float, color: Int, tf: Typeface, align: Paint.Align = Paint.Align.CENTER): TextPaint =
        paint.apply { textSize = size; this.color = color; typeface = tf; textAlign = align }

    /** Draws a single line vertically centered on [y]. */
    fun draw(
        c: Canvas, text: String, x: Float, y: Float, size: Float, color: Int,
        tf: Typeface = Theme.uiFont, align: Paint.Align = Paint.Align.CENTER,
    ) {
        val p = paint(size, color, tf, align)
        val fm = p.fontMetrics
        c.drawText(text, x, y - (fm.ascent + fm.descent) / 2, p)
    }

    fun width(text: String, size: Float, tf: Typeface): Float = paint(size, 0, tf).measureText(text)

    /** Wrapped, centered multi-line text. */
    fun layout(text: String, size: Float, color: Int, width: Int): StaticLayout {
        val p = TextPaint(Paint.ANTI_ALIAS_FLAG).apply { textSize = size; this.color = color; typeface = Theme.uiFont }
        return StaticLayout.Builder.obtain(text, 0, text.length, p, width)
            .setAlignment(Layout.Alignment.ALIGN_CENTER).build()
    }
}

/** Rounded button with a label. Positions are in dp; [scale] scales it around its center. */
class Button(
    var text: String,
    val w: Float,
    val h: Float,
    val fontSize: Float = 20f,
    var color: Int = Theme.button,
    val textColor: Int = Theme.lightText,
    var typeface: Typeface = Theme.uiFont,
    val action: () -> Unit,
) {
    var cx = 0f
    var cy = 0f
    var scale = 1f
    var enabled = true
    var visible = true
    var pressed = false
    var alpha = 1f
    var labelOffsetY = 0f
    var decorate: ((Canvas) -> Unit)? = null

    fun hit(x: Float, y: Float, pad: Float = 0f) =
        abs(x - cx) <= w * scale / 2 + pad && abs(y - cy) <= h * scale / 2 + pad

    fun draw(c: Canvas) {
        if (!visible) return
        c.save()
        c.translate(cx, cy)
        c.scale(scale, scale)
        val a = if (enabled) alpha else 0.45f
        val s = if (pressed) 0.95f else 1f
        P.roundRect(c, 0f, 0f, w * s, h * s, min(h / 2, 14f), color, alpha = if (pressed) a * 0.7f else a)
        Txt.draw(c, text, 0f, labelOffsetY, fontSize, P.withAlpha(textColor, a), typeface)
        decorate?.invoke(c)
        c.restore()
    }
}

/** A full-screen state (menu, level list, game). Sizes are in dp. */
abstract class Screen(val view: GameView) {
    var w = 0f
    var h = 0f
    var insets = Insets()
    private val pressed = mutableMapOf<Int, Button>()

    /** Buttons that currently receive touches, topmost last. */
    abstract fun activeButtons(): List<Button>

    open fun layout() {}
    open fun update(dt: Float) {}
    abstract fun draw(c: Canvas)
    open fun onFreeTouchDown(id: Int, x: Float, y: Float) {}
    open fun onFreeTouchMove(id: Int, x: Float, y: Float) {}
    open fun onFreeTouchUp(id: Int) {}
    /** Returns false to let the system handle Back (exit the app). */
    open fun onBack(): Boolean = false
    open fun onAppPause() {}

    fun touchDown(id: Int, x: Float, y: Float) {
        val b = activeButtons().lastOrNull { it.visible && it.enabled && it.hit(x, y) }
        if (b != null) {
            pressed[id] = b
            b.pressed = true
        } else {
            onFreeTouchDown(id, x, y)
        }
    }

    fun touchMove(id: Int, x: Float, y: Float) {
        if (id !in pressed) onFreeTouchMove(id, x, y)
    }

    fun touchUp(id: Int, x: Float, y: Float, cancelled: Boolean) {
        val b = pressed.remove(id)
        if (b == null) {
            onFreeTouchUp(id)
            return
        }
        b.pressed = false
        if (!cancelled && b.hit(x, y, 10f)) {
            Sound.play(SFX.TAP)
            b.action()
        }
    }

    fun go(to: Screen, fade: Boolean = true) = view.show(to, fade)
}
