package com.example.testapp

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The theme saved by the app's settings, through shared_preferences.
        // Covers a phone that had the choice made before this version.
        val themeMode = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getString("flutter.themeMode", null)
        useDarkLaunchScreen(themeMode == "dark")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Settings calls this the moment the theme changes, so the next launch
        // screen is right even if the app is closed without leaving it first.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "finassist/launch_screen")
            .setMethodCallHandler { call, result ->
                if (call.method == "setDark") {
                    useDarkLaunchScreen(call.arguments == true)
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    /**
     * Android 13 and up let an app choose the theme of its next launch screen,
     * so someone who picked dark mode in FinAssist opens it on a dark screen
     * too. Earlier versions always start on white, the app's default.
     */
    private fun useDarkLaunchScreen(dark: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        splashScreen.setSplashScreenTheme(if (dark) R.style.SplashDark else R.style.SplashLight)
    }
}
