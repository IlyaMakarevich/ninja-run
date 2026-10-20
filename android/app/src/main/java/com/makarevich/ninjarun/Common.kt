package com.makarevich.ninjarun

import android.content.SharedPreferences
import android.graphics.Color
import android.graphics.Typeface

object Theme {
    fun rgb(hex: Int, a: Float = 1f) =
        Color.argb((a * 255).toInt(), (hex shr 16) and 0xFF, (hex shr 8) and 0xFF, hex and 0xFF)

    val screen = rgb(0x8E939E)
    val levelBG = rgb(0xD3D6DD)
    val tile = rgb(0x474C59)
    val text = rgb(0x22252D)
    val lightText = rgb(0xF4F5F7)
    val ninja = rgb(0x121318)
    val scarf = rgb(0xE0393E)
    val gold = rgb(0xF2C230)
    val goldDark = rgb(0xA97D0C)
    val mine = rgb(0xD7263D)
    val drone = rgb(0x3A6EA5)
    val chaser = rgb(0x7B3FA0)
    val turret = rgb(0x50555F)
    val beam = rgb(0xFF3B30)
    val switchOff = rgb(0x8A8F99)
    val accent = rgb(0x2FB463)
    val doorClosed = rgb(0x6B7280)
    val doorPanel = rgb(0x3E434D)
    val launchpad = rgb(0xF2994A)
    val key = rgb(0xE5B80B)
    val wood = rgb(0x8B5E3C)
    val button = rgb(0x2B2F38)

    val logoFont: Typeface = Typeface.create("sans-serif-black", Typeface.NORMAL)
    val titleFont: Typeface = Typeface.create("sans-serif", Typeface.BOLD)
    val uiFont: Typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
    val monoFont: Typeface = Typeface.create(Typeface.MONOSPACE, Typeface.BOLD)
}

object Progress {
    lateinit var prefs: SharedPreferences

    /** Number of levels available to play (at least 1). */
    val unlocked: Int get() = maxOf(1, prefs.getInt("unlocked", 0))

    fun best(level: Int): Float? =
        if (prefs.contains("best_$level")) prefs.getFloat("best_$level", 0f) else null

    fun record(level: Int, timeLeft: Float) {
        val e = prefs.edit()
        if ((best(level) ?: -1f) < timeLeft) e.putFloat("best_$level", timeLeft)
        if (unlocked < level + 2) e.putInt("unlocked", minOf(level + 2, Levels.all.size))
        e.apply()
    }
}

/** Haptic feedback, routed to the game view (set by [GameView]). */
object Haptics {
    var handler: ((Kind) -> Unit)? = null

    enum class Kind { LIGHT, HEAVY, SUCCESS }

    fun light() = handler?.invoke(Kind.LIGHT)
    fun heavy() = handler?.invoke(Kind.HEAVY)
    fun success() = handler?.invoke(Kind.SUCCESS)
}
