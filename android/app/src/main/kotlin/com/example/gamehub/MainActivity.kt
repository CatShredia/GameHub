package com.example.gamehub

import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

/// Скрывает системную панель «Назад / Домой / Обзор». Панель приложения не трогаем.
/// Flutter после первого кадра часто сбрасывает insets — дублируем вызовы.
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        super.onCreate(savedInstanceState)
        hideSystemNavigationBar()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val v = window.decorView
        v.post {
            hideSystemNavigationBar()
            v.postDelayed({ hideSystemNavigationBar() }, 80)
            v.postDelayed({ hideSystemNavigationBar() }, 250)
            v.postDelayed({ hideSystemNavigationBar() }, 600)
        }
    }

    override fun onResume() {
        super.onResume()
        hideSystemNavigationBar()
    }

    override fun onPostResume() {
        super.onPostResume()
        hideSystemNavigationBar()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            hideSystemNavigationBar()
        }
    }

    @Suppress("DEPRECATION")
    private fun hideSystemNavigationBar() {
        // API 30+: controller
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.navigationBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        // Старые флаги — на части прошивок работают надёжнее, чем только insets
        @Suppress("DEPRECATION")
        var flags = (
            View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            window.addFlags(WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        }
        window.decorView.systemUiVisibility = flags

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.apply {
                hide(WindowInsets.Type.navigationBars())
                systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        }
    }
}
