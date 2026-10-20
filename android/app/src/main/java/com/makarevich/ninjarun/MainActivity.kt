package com.makarevich.ninjarun

import android.app.Activity
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import android.window.OnBackInvokedDispatcher

class MainActivity : Activity() {
    private lateinit var gameView: GameView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("ninjarun", MODE_PRIVATE)
        Lang.prefs = prefs
        Progress.prefs = prefs
        Sound.init(this, prefs)

        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        window.attributes = window.attributes.apply {
            layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }

        val debug = (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        val screenArg = if (debug) intent.getStringExtra("screen") else null
        if (debug) intent.getStringExtra("lang")?.let { code -> Lang.entries.firstOrNull { it.code == code }?.let { Lang.current = it } }

        gameView = GameView(this) { v -> initialScreen(v, screenArg) }
        setContentView(gameView)
        hideSystemBars()

        if (Build.VERSION.SDK_INT >= 33) {
            onBackInvokedDispatcher.registerOnBackInvokedCallback(OnBackInvokedDispatcher.PRIORITY_DEFAULT) {
                if (!gameView.back()) finish()
            }
        }
    }

    /** Debug builds accept `--es screen levels|level3` for testing and screenshots. */
    private fun initialScreen(v: GameView, arg: String?): Screen = when {
        arg == "levels" -> LevelSelectScreen(v)
        arg != null && arg.startsWith("level") ->
            arg.removePrefix("level").toIntOrNull()?.takeIf { it in 1..Levels.all.size }
                ?.let { GameScreen(v, it - 1) } ?: MenuScreen(v)
        else -> MenuScreen(v)
    }

    @Deprecated("Used below API 33")
    override fun onBackPressed() {
        if (!gameView.back()) @Suppress("DEPRECATION") super.onBackPressed()
    }

    override fun onResume() {
        super.onResume()
        gameView.resume()
    }

    override fun onPause() {
        gameView.pause()
        super.onPause()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) hideSystemBars()
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent): Boolean =
        gameView.key(keyCode, true) || super.onKeyDown(keyCode, event)

    override fun onKeyUp(keyCode: Int, event: KeyEvent): Boolean =
        gameView.key(keyCode, false) || super.onKeyUp(keyCode, event)

    private fun hideSystemBars() {
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false)
            window.insetsController?.let {
                it.hide(WindowInsets.Type.systemBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
        }
    }
}
