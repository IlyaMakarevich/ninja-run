package com.makarevich.ninjarun

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.os.Build
import android.view.Choreographer
import android.view.HapticFeedbackConstants
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.View
import android.view.WindowInsets

/** Hosts the current [Screen], runs the frame loop and routes input. */
@SuppressLint("ViewConstructor")
class GameView(context: Context, initial: (GameView) -> Screen) : View(context), Choreographer.FrameCallback {
    private val density = resources.displayMetrics.density
    lateinit var screen: Screen
        private set
    private var insets = Insets()
    private var fade = 0f
    private var running = false
    private var lastNanos = 0L

    /** Hardware keys currently held (emulator / keyboard support). */
    val keysDown = mutableSetOf<Int>()

    init {
        isFocusable = true
        isFocusableInTouchMode = true
        Haptics.handler = { kind ->
            val c = when (kind) {
                Haptics.Kind.LIGHT -> HapticFeedbackConstants.CLOCK_TICK
                Haptics.Kind.HEAVY -> HapticFeedbackConstants.LONG_PRESS
                Haptics.Kind.SUCCESS ->
                    if (Build.VERSION.SDK_INT >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
            }
            performHapticFeedback(c)
        }
        screen = initial(this)
    }

    fun show(s: Screen, withFade: Boolean = true) {
        screen = s
        applySize()
        if (withFade) fade = 1f
    }

    private fun applySize() {
        screen.w = width / density
        screen.h = height / density
        screen.insets = insets
        if (width > 0) screen.layout()
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) = applySize()

    override fun onApplyWindowInsets(wi: WindowInsets): WindowInsets {
        val cut = wi.displayCutout
        insets = if (cut != null) Insets(
            cut.safeInsetLeft / density, cut.safeInsetTop / density,
            cut.safeInsetRight / density, cut.safeInsetBottom / density,
        ) else Insets()
        applySize()
        return wi
    }

    fun resume() {
        if (running) return
        running = true
        lastNanos = 0L
        Choreographer.getInstance().postFrameCallback(this)
    }

    fun pause() {
        running = false
        Choreographer.getInstance().removeFrameCallback(this)
        keysDown.clear()
        screen.onAppPause()
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!running) return
        val dt = if (lastNanos == 0L) 1f / 60 else ((frameTimeNanos - lastNanos) / 1e9f).coerceIn(0f, 0.1f)
        lastNanos = frameTimeNanos
        screen.update(dt)
        if (fade > 0) fade = (fade - dt / 0.3f).coerceAtLeast(0f)
        invalidate()
        Choreographer.getInstance().postFrameCallback(this)
    }

    override fun onDraw(canvas: Canvas) {
        canvas.save()
        canvas.scale(density, density)
        screen.draw(canvas)
        if (fade > 0) canvas.drawColor(P.withAlpha(Theme.screen, fade))
        canvas.restore()
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val s = screen
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                val i = e.actionIndex
                s.touchDown(e.getPointerId(i), e.getX(i) / density, e.getY(i) / density)
            }
            MotionEvent.ACTION_MOVE -> for (i in 0 until e.pointerCount) {
                s.touchMove(e.getPointerId(i), e.getX(i) / density, e.getY(i) / density)
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> {
                val i = e.actionIndex
                s.touchUp(e.getPointerId(i), e.getX(i) / density, e.getY(i) / density, cancelled = false)
            }
            MotionEvent.ACTION_CANCEL -> for (i in 0 until e.pointerCount) {
                s.touchUp(e.getPointerId(i), e.getX(i) / density, e.getY(i) / density, cancelled = true)
            }
        }
        return true
    }

    fun key(code: Int, down: Boolean): Boolean {
        val handled = code in GAME_KEYS
        if (handled) { if (down) keysDown.add(code) else keysDown.remove(code) }
        return handled
    }

    /** Handles the system Back gesture. Returns false when the app should close. */
    fun back(): Boolean = screen.onBack()

    companion object {
        val LEFT_KEYS = setOf(KeyEvent.KEYCODE_DPAD_LEFT, KeyEvent.KEYCODE_A)
        val RIGHT_KEYS = setOf(KeyEvent.KEYCODE_DPAD_RIGHT, KeyEvent.KEYCODE_D)
        val JUMP_KEYS = setOf(KeyEvent.KEYCODE_SPACE, KeyEvent.KEYCODE_DPAD_UP, KeyEvent.KEYCODE_W, KeyEvent.KEYCODE_Z)
        private val GAME_KEYS = LEFT_KEYS + RIGHT_KEYS + JUMP_KEYS
    }
}
