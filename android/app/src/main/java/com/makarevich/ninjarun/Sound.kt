package com.makarevich.ninjarun

import android.content.Context
import android.content.SharedPreferences
import android.media.AudioAttributes
import android.media.SoundPool
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.random.Random

enum class SFX {
    JUMP, WALL_JUMP, LAND, GOLD, SWITCH_ON, DOOR_OPEN, KEY, LAUNCHPAD,
    DEATH, EXPLOSION, ZAP, LOCK_ON, GAUSS, ROCKET, WIN, TAP
}

/**
 * Soft retro sound effects synthesized at launch (same recipes as the iOS version).
 * They are written to small WAV files in the cache and played through a SoundPool.
 */
object Sound {
    private const val RATE = 44100
    private const val MASTER = 0.4f
    private lateinit var prefs: SharedPreferences
    private var pool: SoundPool? = null
    private val ids = mutableMapOf<SFX, Int>()

    var enabled: Boolean
        get() = !prefs.getBoolean("muted", false)
        set(v) = prefs.edit().putBoolean("muted", !v).apply()

    fun init(context: Context, prefs: SharedPreferences) {
        this.prefs = prefs
        if (pool != null) return
        val p = SoundPool.Builder()
            .setMaxStreams(10)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_GAME)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            ).build()
        pool = p
        val dir = File(context.cacheDir, "sfx").apply { mkdirs() }
        for (s in SFX.entries) {
            val f = File(dir, "${s.name.lowercase()}.wav")
            writeWav(f, synth(s))
            ids[s] = p.load(f.path, 1)
        }
    }

    fun play(s: SFX) {
        if (!enabled) return
        val id = ids[s] ?: return
        pool?.play(id, 1f, 1f, 1, 0, 1f)
    }

    // region Synthesis

    private class Osc {
        var phase = 0.0
        fun advance(hz: Double): Double {
            phase += hz / RATE
            phase -= floor(phase)
            return phase
        }
        fun sine(hz: Double) = sin(2 * PI * advance(hz))
        fun triangle(hz: Double) = 1 - 4 * abs(advance(hz) - 0.5)
    }

    private class Noise {
        var last = 0.0
        fun white() = Random.nextDouble(-1.0, 1.0)
        /** One-pole low-passed noise; smaller [a] = darker. */
        fun low(a: Double): Double {
            last += a * (white() - last)
            return last * 2.5
        }
    }

    /** Soft attack, smooth release and a two-pole low-pass to take the edge off. */
    private fun render(
        duration: Double, volume: Double, attack: Double = 0.008, cutoff: Double = 2500.0,
        f: (t: Double, k: Double) -> Double,
    ): FloatArray {
        val n = (duration * RATE).toInt()
        val out = FloatArray(n)
        val alpha = 1 - exp(-2 * PI * cutoff / RATE)
        var lp1 = 0.0
        var lp2 = 0.0
        for (i in 0 until n) {
            val t = i.toDouble() / RATE
            val k = t / duration
            val env = min(1.0, t / attack) * min(1.0, (duration - t) / 0.02)
            val x = f(t, k) * env
            lp1 += alpha * (x - lp1)
            lp2 += alpha * (lp1 - lp2)
            out[i] = (lp2 * volume * MASTER).toFloat()
        }
        return out
    }

    private fun decay(k: Double, p: Double = 2.0) = (1 - k).pow(p)

    private fun synth(s: SFX): FloatArray {
        val osc = Osc()
        val osc2 = Osc()
        val noise = Noise()
        return when (s) {
            SFX.JUMP -> render(0.12, 0.10) { _, k -> osc.triangle(260 + 220 * k) * decay(k) }
            SFX.WALL_JUMP -> render(0.13, 0.10) { _, k -> osc.triangle(330 + 260 * k) * decay(k) }
            SFX.LAND -> render(0.08, 0.20, attack = 0.004, cutoff = 600.0) { _, k -> noise.low(0.05) * decay(k, 3.0) }
            SFX.GOLD -> render(0.18, 0.14) { t, k -> osc.sine(if (t < 0.05) 1046.0 else 1318.0) * decay(k, 1.5) }
            SFX.SWITCH_ON -> render(0.18, 0.13) { t, k -> osc.sine(if (t < 0.07) 587.0 else 784.0) * decay(k, 1.5) }
            SFX.DOOR_OPEN -> render(0.36, 0.11) { t, k ->
                osc.triangle(listOf(523.0, 659.0, 784.0)[min(2, (t / 0.12).toInt())]) * decay(k, 1.2)
            }
            SFX.KEY -> render(0.3, 0.13) { _, k -> (osc.sine(1175.0) + 0.4 * osc2.sine(1568.0)) * decay(k) }
            SFX.LAUNCHPAD -> render(0.28, 0.18) { _, k -> osc.sine(160 + 420 * k * k) * decay(k, 1.5) }
            SFX.DEATH -> render(0.5, 0.28, cutoff = 900.0) { _, k ->
                (noise.low(0.12) * 0.8 + osc.triangle(200 - 130 * k) * 0.4) * decay(k)
            }
            SFX.EXPLOSION -> render(0.65, 0.40, attack = 0.005, cutoff = 700.0) { _, k ->
                noise.low(0.06 + 0.08 * (1 - k)) * decay(k, 2.5)
            }
            SFX.ZAP -> render(0.3, 0.10, cutoff = 1800.0) { t, k ->
                osc.triangle(220 + 60 * sin(2 * PI * 40 * t)) * decay(k, 1.5)
            }
            SFX.LOCK_ON -> render(0.1, 0.07) { _, k -> osc.sine(1046.0) * decay(k) }
            SFX.GAUSS -> render(0.32, 0.18, cutoff = 1500.0) { _, k ->
                (osc.sine(900 * decay(k) + 120) * 0.6 + noise.low(0.15) * 0.4) * decay(k, 1.5)
            }
            SFX.ROCKET -> render(0.38, 0.16, attack = 0.04, cutoff = 900.0) { _, k -> noise.low(0.1) * sin(PI * k) }
            SFX.WIN -> render(0.6, 0.12) { t, k ->
                osc.triangle(listOf(523.0, 659.0, 784.0, 1046.0)[min(3, (t / 0.11).toInt())]) * decay(k, 0.8)
            }
            SFX.TAP -> render(0.05, 0.06) { _, k -> osc.sine(700.0) * decay(k) }
        }
    }

    private fun writeWav(file: File, samples: FloatArray) {
        val dataLen = samples.size * 2
        val b = ByteBuffer.allocate(44 + dataLen).order(ByteOrder.LITTLE_ENDIAN)
        b.put("RIFF".toByteArray()).putInt(36 + dataLen).put("WAVE".toByteArray())
        b.put("fmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
            .putInt(RATE).putInt(RATE * 2).putShort(2).putShort(16)
        b.put("data".toByteArray()).putInt(dataLen)
        for (s in samples) b.putShort((clampf(s, -1f, 1f) * 32767).toInt().toShort())
        FileOutputStream(file).use { it.write(b.array()) }
    }

    // endregion
}
