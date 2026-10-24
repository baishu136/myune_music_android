package com.myune.music

import android.app.DownloadManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors

/** Event driven system downloads. No playback thread, timer, or silent install. */
class UpdateDownloadManager(private val context: Context, messenger: BinaryMessenger) {
    private val downloads = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
    private val prefs = context.getSharedPreferences("myune_updates", Context.MODE_PRIVATE)
    private val channel = MethodChannel(messenger, "com.myune.music/updates")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var closed = false
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(c: Context, intent: Intent) {
            if (intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1) == prefs.getLong("id", -2)) {
                if (!closed) channel.invokeMethod("changed", null)
            }
        }
    }
    private var registered = false
    init {
        try {
            val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            else @Suppress("DEPRECATION") context.registerReceiver(receiver, filter)
            registered = true
        } catch (_: Exception) { }
        channel.setMethodCallHandler { call, result ->
            if (closed) { result.error("closed", "下载管理已关闭", null); return@setMethodCallHandler }
            if (call.method == "open") {
                worker.execute {
                    try {
                        check(queryStatus()["state"] == "complete") { "安装包尚未下载完成或校验未通过" }
                        val uri = downloads.getUriForDownloadedFile(prefs.getLong("id", -1)) ?: error("安装包已不存在")
                        main.post {
                            if (!closed) try {
                                val intent = if (Build.VERSION.SDK_INT >= 26 && !context.packageManager.canRequestPackageInstalls())
                                    Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${context.packageName}"))
                                else Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
                                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                                result.success(null)
                            } catch (e: Exception) { result.error("open_update", e.message, null) }
                        }
                    } catch (e: Exception) { main.post { if (!closed) result.error("open_update", e.message, null) } }
                }
            } else worker.execute {
                try {
                    val value: Any? = when (call.method) {
                        "enabled" -> {
                            val enabled = call.arguments == true
                            prefs.edit().putBoolean("enabled", enabled).apply()
                            if (!enabled && prefs.getBoolean("automatic", false)) {
                                val state = queryStatus()
                                if (state["state"] in listOf("queued", "downloading", "waiting")) {
                                    downloads.remove(prefs.getLong("id", -1))
                                    prefs.edit().remove("id").apply()
                                }
                            }
                            null
                        }
                        "status" -> queryStatus()
                        "download" -> {
                            val automatic = call.argument<Boolean>("automatic") == true
                            check(!automatic || prefs.getBoolean("enabled", true)) { "自动下载已关闭" }
                            val url = call.argument<String>("url") ?: error("缺少地址")
                            val uri = Uri.parse(url)
                            check(uri.scheme == "https" && uri.host == "github.com" && uri.userInfo == null &&
                                uri.path?.startsWith("/baishu136/myune_music_android/releases/download/") == true &&
                                uri.path?.endsWith("-arm64-v8a.apk") == true) { "更新地址不属于项目正式附件" }
                            val size = call.argument<Number>("size")?.toLong() ?: 0
                            check(size in 1..314572800L) { "安装包大小无效" }
                            val version = call.argument<String>("version") ?: error("缺少版本")
                            check(Regex("[0-9]+\\.[0-9]+\\.[0-9]+-android\\.[0-9]+").matches(version)) { "版本无效" }
                            val sha = call.argument<String>("sha256")
                            check(sha == null || Regex("[a-fA-F0-9]{64}").matches(sha)) { "校验值无效" }
                            val previous = queryStatus()
                            if (prefs.getString("url", null) == url && previous["state"] in listOf("queued", "downloading", "waiting", "complete")) {
                                previous
                            } else {
                                val oldId = prefs.getLong("id", -1)
                                // Only cancel this application's own unfinished update.
                                if (oldId >= 0 && previous["state"] in listOf("queued", "downloading", "waiting")) downloads.remove(oldId)
                                val name = "Myune-$version-${UUID.randomUUID()}.apk"
                                val file = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS), name)
                                val request = DownloadManager.Request(uri)
                                    .setTitle("Myune Music $version")
                                    .setMimeType("application/vnd.android.package-archive")
                                    .setAllowedOverRoaming(false)
                                    .setAllowedOverMetered(!automatic)
                                    .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                                    .setDestinationInExternalFilesDir(context, Environment.DIRECTORY_DOWNLOADS, name)
                                val id = downloads.enqueue(request)
                                prefs.edit().putLong("id", id).putString("url", url).putString("version", version)
                                    .putString("path", file.absolutePath).putLong("size", size).putString("sha256", sha)
                                    .putBoolean("automatic", automatic).remove("verified").apply()
                                queryStatus()
                            }
                        }
                        else -> throw IllegalArgumentException("未知下载操作")
                    }
                    main.post { if (!closed) result.success(value) }
                } catch (e: Exception) { main.post { if (!closed) result.error("update_download", e.message, null) } }
            }
        }
    }
    @Suppress("DEPRECATION")
    private fun verify(file: File, id: Long) {
        check(file.isFile && file.length() == prefs.getLong("size", -1)) { "更新附件不完整，请重试" }
        val fingerprint = "$id:${file.length()}:${file.lastModified()}"
        if (prefs.getString("verified", null) == fingerprint) return
        val expected = prefs.getString("sha256", null)
        if (expected != null) {
            val hash = MessageDigest.getInstance("SHA-256")
            file.inputStream().buffered().use { stream ->
                val buffer = ByteArray(65536)
                while (true) { val n = stream.read(buffer); if (n < 0) break; hash.update(buffer, 0, n) }
            }
            check(hash.digest().joinToString("") { "%02x".format(it) }.equals(expected, true)) { "更新附件SHA256不匹配，请重试" }
        }
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val info = context.packageManager.getPackageArchiveInfo(file.absolutePath, flags) ?: error("不是有效的Android安装包")
        check(info.packageName == "com.myune.music") { "安装包不属于Myune Music" }
        val version = prefs.getString("version", "")!!
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
        check("${info.versionName}-android.${if (code >= 1000) code % 1000 else code}" == version) { "附件版本与发布信息不符" }
        val local = context.packageManager.getPackageInfo(context.packageName, flags)
        val actual = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        val installed = if (Build.VERSION.SDK_INT >= 28) local.signingInfo?.apkContentsSigners else local.signatures
        check(actual != null && installed != null && actual.toSet() == installed.toSet()) { "安装包签名与当前应用不一致" }
        prefs.edit().putString("verified", fingerprint).apply()
    }
    private fun queryStatus(): Map<String, Any?> {
        val id = prefs.getLong("id", -1)
        if (id < 0) return mapOf("state" to "none")
        downloads.query(DownloadManager.Query().setFilterById(id)).use { cursor ->
            if (!cursor.moveToFirst()) return mapOf("state" to "none")
            val status = cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_STATUS))
            val state = when (status) {
                DownloadManager.STATUS_SUCCESSFUL -> "complete"
                DownloadManager.STATUS_FAILED -> "failed"
                DownloadManager.STATUS_PAUSED -> "waiting"
                DownloadManager.STATUS_RUNNING -> "downloading"
                else -> "queued"
            }
            var reason: String? = if (state == "failed") "系统下载失败（${cursor.getInt(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_REASON))}）" else null
            if (state == "complete") try { verify(File(prefs.getString("path", "")!!), id) }
                catch (e: Exception) { reason = e.message }
            return mapOf("state" to if (state == "complete" && reason != null) "failed" else state,
                "version" to prefs.getString("version", ""), "reason" to reason,
                "bytes" to cursor.getLong(cursor.getColumnIndexOrThrow(DownloadManager.COLUMN_BYTES_DOWNLOADED_SO_FAR)),
                "size" to prefs.getLong("size", 0))
        }
    }
    fun dispose() {
        closed = true
        channel.setMethodCallHandler(null)
        if (registered) context.unregisterReceiver(receiver)
        worker.shutdown()
    }
}
