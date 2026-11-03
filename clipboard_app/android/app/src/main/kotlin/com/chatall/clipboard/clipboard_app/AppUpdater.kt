package com.chatall.clipboard.clipboard_app

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** `chat.clawkit.clipboard/updater`: background APK download, verification and hand-off to the system installer. */
internal class AppUpdater(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val busy = AtomicBoolean(false)
    private val downloads = UpdateDownloadStore(activity.applicationContext)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "version" -> result.success(installedVersion())
            "canInstall" -> result.success(Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls())
            "snapshot" -> run(result) { downloads.snapshot() }
            "cancel" -> run(result) { downloads.cancel(); null }
            "download" -> run(result) {
                val size = (call.argument<Number>("size") ?: 0).toLong()
                downloads.start(call.argument<String>("url")!!, call.argument<String>("sha256")!!, size, call.argument<String>("version")!!)
            }
            "install" -> install(result)
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun installedVersion(): Map<String, Any?> {
        val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        return mapOf("name" to info.versionName, "code" to code)
    }

    private fun run(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try {
                val value = action()
                main.post { result.success(value) }
            } catch (e: Exception) {
                main.post { result.error("UPDATE_FAILED", e.message ?: "更新失败，请重试", null) }
            }
        }
    }

    /** Always a foreground user action; a finished background download only becomes "ready". */
    private fun install(result: MethodChannel.Result) {
        if (!busy.compareAndSet(false, true)) { result.error("BUSY", "更新正在处理中", null); return }
        worker.execute {
            try {
                val apk = downloads.verifyForInstall()
                main.post {
                    try {
                        if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                            result.success("permission")
                        } else {
                            val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
                            activity.startActivity(Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION))
                            result.success("installer")
                        }
                    } catch (e: Exception) {
                        result.error("INSTALL_FAILED", e.message ?: "无法打开系统安装界面", null)
                    } finally { busy.set(false) }
                }
            } catch (e: Exception) {
                busy.set(false)
                main.post { result.error("INSTALL_FAILED", e.message ?: "请重新下载更新", null) }
            }
        }
    }
}
