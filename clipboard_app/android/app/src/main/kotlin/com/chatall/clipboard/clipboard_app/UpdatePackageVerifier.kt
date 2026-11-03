package com.chatall.clipboard.clipboard_app

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.os.Build
import java.io.File
import java.security.MessageDigest

/** Verify bytes, package identity and signer before handing anything to Android's installer. */
internal object UpdatePackageVerifier {
  @Suppress("DEPRECATION")
  fun verify(context: Context, file: File, sha256: String, size: Long, version: String) {
    require(file.isFile && file.length() == size) { "安装包大小不一致，请重新下载" }
    val digest = MessageDigest.getInstance("SHA-256")
    file.inputStream().buffered().use { input ->
      val buffer = ByteArray(65536)
      while (true) {
        val n = input.read(buffer)
        if (n < 0) break
        digest.update(buffer, 0, n)
      }
    }
    require(digest.digest().joinToString("") { "%02x".format(it) } == sha256) { "安装包校验失败，请重新下载" }
    val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
    val archive = context.packageManager.getPackageArchiveInfo(file.path, flags) ?: error("无法读取安装包")
    val installed = context.packageManager.getPackageInfo(context.packageName, flags)
    require(archive.packageName == context.packageName && archive.versionName == version) { "安装包应用或版本不匹配" }
    val newCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
    val oldCode = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
    require(newCode > oldCode) { "该安装包不是更新版本，请重新检查更新" }
    require(signatures(archive) == signatures(installed) && signatures(installed).isNotEmpty()) { "安装包签名不匹配，已停止更新" }
  }

  @Suppress("DEPRECATION")
  private fun signatures(info: PackageInfo): Set<String> {
    val signers = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
    return signers.orEmpty().map { s ->
      MessageDigest.getInstance("SHA-256").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }
    }.toSet()
  }
}
