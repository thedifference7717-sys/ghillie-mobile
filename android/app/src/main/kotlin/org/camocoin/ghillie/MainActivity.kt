package org.camocoin.ghillie

import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity: the fingerprint prompt (BiometricPrompt) needs a FragmentActivity.
class MainActivity : FlutterFragmentActivity() {
    // Called by lib/ui/sensitive.dart while the 25 words are on screen: no screenshots, recordings or recents thumbnail.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.camocoin.ghillie/secure").setMethodCallHandler { call, result ->
            when (call.method) {
                "on" -> { window.addFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
                "off" -> { window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
}
