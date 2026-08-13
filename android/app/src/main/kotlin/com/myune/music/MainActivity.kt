package com.myune.music

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.myune.music/desktop_lyrics"
    private lateinit var channel: MethodChannel
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
        DesktopLyricsService.setEventSink(null)
        super.onDestroy()
    }
}
