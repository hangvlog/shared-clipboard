package com.chatall.clipboard.clipboard_app

import android.content.ClipboardManager
import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var listening = false
    private val clipboard by lazy {
        getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    }
    private val listener = ClipboardManager.OnPrimaryClipChangedListener {
        if (listening && hasWindowFocus()) channel?.invokeMethod("changed", null)
    }

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "chat.clawkit.clipboard/events")
    }

    override fun onResume() {
        super.onResume()
        if (!listening) {
            clipboard.addPrimaryClipChangedListener(listener)
            listening = true
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // On Android 10+, clipboard access requires foreground window focus.
        if (hasFocus && listening) channel?.invokeMethod("changed", null)
    }

    override fun onPause() {
        if (listening) clipboard.removePrimaryClipChangedListener(listener)
        listening = false
        super.onPause()
    }

    override fun onDestroy() {
        if (listening) clipboard.removePrimaryClipChangedListener(listener)
        channel = null
        super.onDestroy()
    }
}
