package com.myune.music

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val channelName = "com.myune.music/desktop_lyrics"
    private val coverEditorChannelName = "com.myune.music/cover_editor"
    private lateinit var channel: MethodChannel
    private val coverEditorExecutor = Executors.newSingleThreadExecutor()
    @Volatile private var destroyed = false
    private var pendingGalleryResult: MethodChannel.Result? = null
    private var permissionRequestPending = false
    private var permissionEnableOnGrant = true
    private val permissionPreferences by lazy {
        getSharedPreferences("desktop_lyrics_permission", MODE_PRIVATE)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        DesktopLyricsService.setEventSink { type, payload ->
            channel.invokeMethod("event", mapOf("type" to type) + payload)
        }
        channel.setMethodCallHandler { call, result ->
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<String, Any?> ?: emptyMap()
            when (call.method) {
                "hasPermission" -> result.success(Settings.canDrawOverlays(this))
                "requestPermission" -> {
                    permissionRequestPending = true
                    permissionEnableOnGrant = args["enableOnGrant"] as? Boolean ?: true
                    permissionPreferences.edit()
                        .putBoolean("pending", true)
                        .putBoolean("enable_on_grant", permissionEnableOnGrant)
                        .apply()
                    try {
                        startActivity(
                            Intent(
                                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                Uri.parse("package:$packageName"),
                            ),
                        )
                    } catch (_: Exception) {
                        permissionRequestPending = false
                        permissionPreferences.edit()
                            .remove("pending")
                            .remove("enable_on_grant")
                            .apply()
                        result.error("overlay_settings_unavailable", "无法打开悬浮窗权限设置", null)
                        return@setMethodCallHandler
                    }
                    result.success(null)
                }
                "show" -> {
                    DesktopLyricsService.showOrUpdate(applicationContext, args)
                    result.success(null)
                }
                "update" -> {
                    DesktopLyricsService.showOrUpdate(applicationContext, args)
                    result.success(null)
                }
                "hide" -> {
                    DesktopLyricsService.hide(applicationContext)
                    result.success(null)
                }
                "setLocked" -> {
                    DesktopLyricsService.setLocked(
                        applicationContext,
                        args["locked"] as? Boolean ?: false,
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            coverEditorChannelName,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "pickImageFromGallery" -> openGalleryPicker(result)
                "replaceEmbeddedCover" -> {
                    val path = call.argument<String>("path")
                    val imageBytes = call.argument<ByteArray>("imageBytes")
                    if (path.isNullOrBlank() || imageBytes == null || imageBytes.isEmpty()) {
                        result.error("invalid_arguments", "音频路径或封面图片无效", null)
                        return@setMethodCallHandler
                    }
                    coverEditorExecutor.execute {
                        try {
                            AudioCoverEditor.replaceEmbeddedCover(path, imageBytes)
                            runOnUiThread {
                                if (!destroyed) result.success(null)
                            }
                        } catch (error: Exception) {
                            runOnUiThread {
                                if (!destroyed) {
                                    result.error(
                                        "cover_write_failed",
                                        error.message ?: "替换文件封面失败",
                                        null,
                                    )
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun openGalleryPicker(result: MethodChannel.Result) {
        if (pendingGalleryResult != null) {
            result.error("picker_busy", "系统相册已打开", null)
            return
        }
        val modernIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply { type = "image/*" }
        } else {
            null
        }
        val legacyIntent = Intent(
            Intent.ACTION_PICK,
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
        ).apply { type = "image/*" }
        val intent = if (modernIntent?.resolveActivity(packageManager) != null) {
            modernIntent
        } else {
            legacyIntent
        }
        if (intent.resolveActivity(packageManager) == null) {
            result.error("gallery_unavailable", "设备上没有可用的系统相册", null)
            return
        }
        pendingGalleryResult = result
        try {
            startActivityForResult(intent, galleryRequestCode)
        } catch (error: Exception) {
            pendingGalleryResult = null
            result.error("gallery_open_failed", error.message ?: "无法打开系统相册", null)
        }
    }

    @Deprecated("Deprecated in Android; retained for the minSdk 24 gallery fallback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != galleryRequestCode) return
        val result = pendingGalleryResult ?: return
        pendingGalleryResult = null
        if (resultCode != Activity.RESULT_OK) {
            result.success(null)
            return
        }
        val uri = data?.data
        if (uri == null) {
            result.error("gallery_empty_result", "系统相册没有返回图片", null)
            return
        }
        coverEditorExecutor.execute {
            try {
                val cachedPath = copyGalleryImageToCache(uri)
                runOnUiThread {
                    if (!destroyed) result.success(cachedPath)
                }
            } catch (error: Exception) {
                runOnUiThread {
                    if (!destroyed) {
                        result.error(
                            "gallery_copy_failed",
                            error.message ?: "无法读取所选图片",
                            null,
                        )
                    }
                }
            }
        }
    }

    private fun copyGalleryImageToCache(uri: Uri): String {
        val directory = File(cacheDir, "cover_picker").apply { mkdirs() }
        directory.listFiles()?.forEach { file ->
            if (System.currentTimeMillis() - file.lastModified() > pickerCacheLifetimeMs) {
                file.delete()
            }
        }
        val extension = when (contentResolver.getType(uri)?.lowercase()) {
            "image/png" -> ".png"
            "image/webp" -> ".webp"
            "image/gif" -> ".gif"
            else -> ".jpg"
        }
        val target = File.createTempFile("cover_", extension, directory)
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().buffered().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        total += read
                        if (total > maxGalleryImageBytes) {
                            throw IOException("所选图片超过 64 MB")
                        }
                        output.write(buffer, 0, read)
                    }
                }
            } ?: throw IOException("无法打开所选图片")
            return target.path
        } catch (error: Exception) {
            target.delete()
            throw error
        }
    }

    override fun onResume() {
        super.onResume()
        val pending = permissionRequestPending || permissionPreferences.getBoolean("pending", false)
        if (pending && ::channel.isInitialized) {
            val enableOnGrant = if (permissionRequestPending) {
                permissionEnableOnGrant
            } else {
                permissionPreferences.getBoolean("enable_on_grant", true)
            }
            permissionRequestPending = false
            permissionPreferences.edit()
                .remove("pending")
                .remove("enable_on_grant")
                .apply()
            channel.invokeMethod(
                "permissionChanged",
                mapOf(
                    "granted" to Settings.canDrawOverlays(this),
                    "enableOnGrant" to enableOnGrant,
                ),
            )
        }
    }

    override fun onStart() {
        super.onStart()
        DesktopLyricsService.setAppVisible(true)
    }

    override fun onStop() {
        DesktopLyricsService.setAppVisible(false)
        super.onStop()
    }

    override fun onDestroy() {
        destroyed = true
        DesktopLyricsService.setEventSink(null)
        pendingGalleryResult?.error("activity_destroyed", "页面已关闭", null)
        pendingGalleryResult = null
        coverEditorExecutor.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val galleryRequestCode = 41420
        private const val maxGalleryImageBytes = 64L * 1024L * 1024L
        private const val pickerCacheLifetimeMs = 24L * 60L * 60L * 1000L
    }
}
