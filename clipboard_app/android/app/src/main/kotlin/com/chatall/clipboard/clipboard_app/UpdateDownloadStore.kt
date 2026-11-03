package com.chatall.clipboard.clipboard_app

import android.app.DownloadManager
import android.content.Context
import android.net.Uri
import android.os.Environment
import java.io.File

/** Android's DownloadManager owns the transfer, so it continues after the app leaves the foreground. */
internal class UpdateDownloadStore(private val context: Context) {
    private val manager get() = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs get() = context.getSharedPreferences("shared-clipboard-update", 0)
    val apk: File
        get() = File(requireNotNull(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS)) {
            "无法访问更新目录，请检查剩余空间"
        }, "shared-clipboard-updates/update.apk")

    fun start(url: String, sha256: String, size: Long, version: String): Map<String, Any?> {
        val uri = Uri.parse(url)
        require(uri.scheme == "https" && !uri.host.isNullOrEmpty() && uri.userInfo == null) { "更新只允许安全下载地址" }
        require(Regex("[a-f0-9]{64}").matches(sha256) && size in 1..200L * 1024 * 1024) { "更新包校验信息不完整" }
        require(Regex("[0-9]+\\.[0-9]+\\.[0-9]+").matches(version)) { "更新版本无效" }
        if (prefs.getString("sha256", null) == sha256 && prefs.getString("version", null) == version) {
            val current = snapshot()
            if (current["stage"] !in listOf("idle", "error")) return current
        }
        cancel()
        apk.parentFile!!.mkdirs()
        require(!apk.exists() || apk.delete()) { "无法替换旧安装包" }
        val request = DownloadManager.Request(uri)
            .setTitle("共享剪贴板更新 $version")
            .setDescription("正在下载安装包，可退出应用")
            .setMimeType("application/octet-stream")
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(false)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE)
            .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, "shared-clipboard-updates/update.apk")
        val id = manager.enqueue(request)
        if (!prefs.edit().clear().putLong("id", id).putString("sha256", sha256)
                .putLong("size", size).putString("version", version).commit()) {
            manager.remove(id)
            error("无法保存更新任务，请重试")
        }
        return snapshot()
    }

    fun snapshot(): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>("stage" to "idle")
        val id = prefs.getLong("id", -1)
        if (id < 0) return result
        val size = prefs.getLong("size", 0)
        result["version"] = prefs.getString("version", "")
        result["sha256"] = prefs.getString("sha256", "")
        result["total"] = size
        result["received"] = 0L
        try {
            manager.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
                require(cursor != null && cursor.moveToFirst()) { "系统下载任务已移除，请重新下载" }
                val received = cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR))
                result["received"] = received.coerceAtLeast(0)
                when (cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))) {
                    DownloadManager.STATUS_SUCCESSFUL -> {
                        // Re-verify on every reattachment; DownloadManager's success alone is not trusted.
                        if (!prefs.getBoolean("verified", false) || !apk.isFile || apk.length() != size) {
                            UpdatePackageVerifier.verify(context, apk, prefs.getString("sha256", "")!!, size, prefs.getString("version", "")!!)
                            check(prefs.edit().putBoolean("verified", true).commit()) { "无法保存校验结果" }
                        }
                        result["stage"] = "ready"
                    }
                    DownloadManager.STATUS_FAILED -> error("下载失败（${cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))}），请重试")
                    DownloadManager.STATUS_PAUSED -> result["stage"] = "paused"
                    else -> result["stage"] = "downloading"
                }
            }
        } catch (e: Exception) {
            result["stage"] = "error"
            result["error"] = e.message ?: "读取更新任务失败，请重试"
        }
        return result
    }

    fun verifyForInstall(): File {
        require(snapshot()["stage"] == "ready") { "安装包尚未准备好，请重新检查更新" }
        UpdatePackageVerifier.verify(context, apk, prefs.getString("sha256", "")!!,
            prefs.getLong("size", 0), prefs.getString("version", "")!!)
        return apk
    }

    fun cancel() {
        val id = prefs.getLong("id", -1)
        if (id >= 0) manager.remove(id)
        check(prefs.edit().clear().commit()) { "无法保存取消状态" }
    }
}
