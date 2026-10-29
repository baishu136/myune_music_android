package com.myune.music

import android.content.Context
import android.content.Intent
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.app.PendingIntent
import android.hardware.usb.UsbConstants
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioMixerAttributes
import android.media.MediaRouter2
import android.media.MediaRouter
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.UUID
import androidx.annotation.Keep

/** Inventory and actual app-owned AAudio stream reports; never enters communication mode. */
@Keep
class AudioOutputManager(private val context: Context, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    companion object {
        private val main = Handler(Looper.getMainLooper())
        private var active: AudioOutputManager? = null
        private val connectionSession = UUID.randomUUID().toString()
        @JvmStatic external fun nativeInitialize()
        @JvmStatic external fun nativeDetach()
        @JvmStatic external fun nativeSnapshot(): LongArray
        @JvmStatic fun onNativeChanged() { main.post { active?.emit() } }
    }
    private val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val usb = context.getSystemService(Context.USB_SERVICE) as UsbManager
    private val methods = MethodChannel(messenger, "com.myune.music/audio_output")
    private val events = EventChannel(messenger, "com.myune.music/audio_output_events")
    private var sink: EventChannel.EventSink? = null
    private var mixerDevice: AudioDeviceInfo? = null
    private var deviceCallbackRegistered = false
    private var receiverRegistered = false
    private var routerRegistered = false
    private var mixerListener: Any? = null
    private var available = false
    private var closed = false
    private val usbIdentityAction = "${context.packageName}.USB_AUDIO_IDENTITY"
    private var pendingIdentity: Int? = null
    private var identityNotice: String? = null
    private val identityReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (intent.action != usbIdentityAction) return
            @Suppress("DEPRECATION") val device = intent.getParcelableExtra<UsbDevice>(UsbManager.EXTRA_DEVICE)
            if (device == null || device.deviceId != pendingIdentity) return
            pendingIdentity = null
            identityNotice = if (usb.hasPermission(device)) "设备标识权限已授权" else "设备标识权限被拒绝，同步设置仅用于本次连接"
            emit()
        }
    }
    private var systemRouteRevision = 0
    private var snapshotRevision = 0L
    private val router = context.getSystemService(Context.MEDIA_ROUTER_SERVICE) as MediaRouter
    private val routeCallback = object : MediaRouter.SimpleCallback() {
        override fun onRouteSelected(router: MediaRouter, type: Int, info: MediaRouter.RouteInfo) {
            systemRouteRevision++; emit()
        }
    }
    private val connectionKeys = mutableMapOf<Int, String>()
    private val attributes = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_MUSIC).build()
    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(devices: Array<out AudioDeviceInfo>) { emit() }
        override fun onAudioDevicesRemoved(devices: Array<out AudioDeviceInfo>) {
            devices.forEach { connectionKeys.remove(it.id) }
            if (devices.any { it.id == mixerDevice?.id }) clearMixer()
            emit()
        }
    }
    init {
        active = this
        try { System.loadLibrary("myune"); nativeInitialize(); available = true } catch (_: LinkageError) { }
        try { manager.registerAudioDeviceCallback(callback, main); deviceCallbackRegistered = true } catch (_: Exception) { }
        try {
            if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(identityReceiver, IntentFilter(usbIdentityAction), Context.RECEIVER_NOT_EXPORTED)
            else @Suppress("DEPRECATION") context.registerReceiver(identityReceiver, IntentFilter(usbIdentityAction))
            receiverRegistered = true
        } catch (_: Exception) { }
        try { router.addCallback(MediaRouter.ROUTE_TYPE_LIVE_AUDIO, routeCallback, MediaRouter.CALLBACK_FLAG_UNFILTERED_EVENTS); routerRegistered = true } catch (_: Exception) { }
        if (Build.VERSION.SDK_INT >= 34) try {
            val listener = AudioManager.OnPreferredMixerAttributesChangedListener { _, _, _ -> emit() }
            manager.addOnPreferredMixerAttributesChangedListener(context.mainExecutor, listener)
            mixerListener = listener
        } catch (_: Exception) { }
        methods.setMethodCallHandler(::handle)
        events.setStreamHandler(this)
    }
    override fun onListen(arguments: Any?, listener: EventChannel.EventSink) { sink = listener; emit() }
    override fun onCancel(arguments: Any?) { sink = null }
    private fun hash(value: String) = MessageDigest.getInstance("SHA-256").digest(value.toByteArray()).joinToString("") { "%02x".format(it) }
    private fun isUsb(device: AudioDeviceInfo) = device.type == AudioDeviceInfo.TYPE_USB_DEVICE || device.type == AudioDeviceInfo.TYPE_USB_HEADSET || device.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
    private fun typeName(type: Int): String = when (type) {
        AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "手机扬声器"
        AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "听筒"
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> "有线耳机"
        AudioDeviceInfo.TYPE_USB_DEVICE, AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_ACCESSORY -> "USB 音频"
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO, 26, 27, 30 -> "蓝牙音频"
        AudioDeviceInfo.TYPE_HDMI, AudioDeviceInfo.TYPE_HDMI_ARC, 29 -> "HDMI"
        else -> "系统媒体输出"
    }
    private fun identity(device: AudioDeviceInfo): Pair<String, Boolean> {
        val address = try { device.address.trim() } catch (_: SecurityException) { "" }
        if (device.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER || device.type == AudioDeviceInfo.TYPE_BUILTIN_EARPIECE)
            return Pair("builtin:${device.type}", true)
        // USB ALSA card/device numbers and anonymous addresses change on reconnect.
        // Without an unambiguous serial we intentionally keep a session profile.
        if (isUsb(device)) {
            val physical = uniqueUsbDevice(device)
            val serial = try { if (physical != null && usb.hasPermission(physical)) physical.serialNumber else null } catch (_: SecurityException) { null }
            if (!serial.isNullOrBlank()) return Pair("usb:" + hash("${physical!!.vendorId}|${physical.productId}|$serial"), true)
        }
        val wireless = device.type in setOf(AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, 26, 27, 30)
        if (wireless && Regex("(?i)([0-9a-f]{2}:){5}[0-9a-f]{2}").matches(address) && address != "00:00:00:00:00:00" && address != "02:00:00:00:00:00")
            return Pair("endpoint:" + hash("${device.type}|$address"), true)
        return Pair(connectionKeys.getOrPut(device.id) { "connection:$connectionSession:${UUID.randomUUID()}" }, false)
    }
    private fun uniqueUsbDevice(device: AudioDeviceInfo): UsbDevice? {
        if (!isUsb(device)) return null
        val outputs = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter { isUsb(it) }
        val physical = usb.deviceList.values.filter { d -> (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_AUDIO } }
        if (outputs.size != 1 || physical.size != 1) return null
        return physical.single().takeIf { !it.productName.isNullOrBlank() && it.productName.toString().trim().equals(device.productName.toString().trim(), ignoreCase = true) }
    }
    private fun formats(device: AudioDeviceInfo): List<AudioMixerAttributes> =
        if (Build.VERSION.SDK_INT >= 34 && isUsb(device)) try { manager.getSupportedMixerAttributes(device) } catch (_: Exception) { emptyList() } else emptyList()
    private fun formatMap(format: AudioFormat) = mapOf("sampleRate" to format.sampleRate, "encoding" to format.encoding, "channels" to format.channelCount, "channelMask" to format.channelMask)
    private fun snapshot(): Map<String, Any?> {
        val notice = identityNotice
        identityNotice = null
        val report = if (available) try { nativeSnapshot() } catch (_: LinkageError) { LongArray(18) } else LongArray(18)
        val devices = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).filter { it.isSink }
        val currentId = if (report.getOrElse(1) { 0 } == 1L) report.getOrElse(2) { 0 }.toInt() else 0
        // Public API reports anticipated media routing, not a per-track proof.
        // Keep it separate from AAudio stream data and never guess by name.
        val systemMediaDeviceIds = if (Build.VERSION.SDK_INT >= 33) try {
            manager.getAudioDevicesForAttributes(attributes).map { it.id }
        } catch (_: Exception) { emptyList<Int>() } else emptyList<Int>()
        val inventory = devices.map { device ->
            val (key, stable) = identity(device)
            mapOf(
                "id" to device.id, "name" to device.productName.toString(), "type" to device.type,
                "connection" to typeName(device.type), "profileKey" to key, "persistentIdentity" to stable,
                "sampleRates" to device.sampleRates.toList(), "encodings" to device.encodings.toList(), "channelCounts" to device.channelCounts.toList(),
                "usb" to isUsb(device), "current" to (currentId == device.id),
                "directSelectable" to (available && Build.VERSION.SDK_INT >= 26 && device.type !in setOf(AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_TELEPHONY, AudioDeviceInfo.TYPE_REMOTE_SUBMIX, 28)),
                "mixerFormats" to formats(device).map { mapOf("format" to formatMap(it.format), "bitPerfect" to (it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT)) }
            )
        }
        val mixer = if (Build.VERSION.SDK_INT >= 34 && mixerDevice != null) try { manager.getPreferredMixerAttributes(attributes, mixerDevice!!) } catch (_: Exception) { null } else null
        return mapOf(
            "sdk" to Build.VERSION.SDK_INT, "snapshotRevision" to ++snapshotRevision, "bridgeAvailable" to available, "systemRouteRevision" to systemRouteRevision, "identityNotice" to notice,
            "devices" to inventory, "stream" to report.toList(), "currentId" to currentId,
            "systemMediaDeviceIds" to systemMediaDeviceIds,
            "routeVerified" to (currentId != 0 && devices.any { it.id == currentId }),
            "mixerConfirmed" to (Build.VERSION.SDK_INT >= 34 && mixer?.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT),
            "usbDevices" to usb.deviceList.values.filter { d -> (0 until d.interfaceCount).any { d.getInterface(it).interfaceClass == UsbConstants.USB_CLASS_AUDIO } }.map { d ->
                mapOf("name" to (d.productName ?: "USB 音频设备"), "vendorId" to d.vendorId, "productId" to d.productId, "permission" to usb.hasPermission(d))
            }
        )
    }
    private fun emit() {
        if (closed) return
        if (Looper.myLooper() != Looper.getMainLooper()) { main.post { emit() }; return }
        try { sink?.success(snapshot()) } catch (e: Exception) { sink?.error("audio_inventory", e.message, null) }
    }
    private fun clearMixer() {
        if (Build.VERSION.SDK_INT >= 34) mixerDevice?.let { try { manager.clearPreferredMixerAttributes(attributes, it) } catch (_: Exception) { } }
        mixerDevice = null
    }
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "snapshot" -> result.success(snapshot())
                "systemPicker" -> {
                    var shown = false
                    if (Build.VERSION.SDK_INT >= 34) shown = MediaRouter2.getInstance(context).showSystemOutputSwitcher()
                    if (!shown) {
                        val intent = Intent(if (Build.VERSION.SDK_INT >= 29) Settings.Panel.ACTION_VOLUME else Settings.ACTION_SOUND_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                    }
                    result.success(true)
                }
                "clearMixer" -> { clearMixer(); emit(); result.success(true) }
                "requestUsbIdentity" -> {
                    if (!receiverRegistered) throw IllegalStateException("系统未允许接收 USB 权限结果")
                    val id = call.argument<Int>("id")
                    val output = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.id == id } ?: throw IllegalStateException("设备已断开")
                    val physical = uniqueUsbDevice(output) ?: throw IllegalStateException("系统无法唯一对应此 USB 设备，不会按名称猜测身份")
                    if (usb.hasPermission(physical)) { result.success(true); emit() }
                    else {
                        pendingIdentity = physical.deviceId
                        val flags = PendingIntent.FLAG_UPDATE_CURRENT or (if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0)
                        val permission = PendingIntent.getBroadcast(context, physical.deviceId, Intent(usbIdentityAction).setPackage(context.packageName), flags)
                        usb.requestPermission(physical, permission)
                        result.success(false)
                    }
                }
                "requestMixer" -> {
                    if (Build.VERSION.SDK_INT < 34) throw IllegalStateException("系统未提供 USB Bit-Perfect 混音器接口")
                    val id = call.argument<Int>("id")
                    val device = manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).firstOrNull { it.id == id } ?: throw IllegalStateException("设备已断开")
                    val rate = call.argument<Int>("sampleRate")
                    val encoding = call.argument<Int>("encoding")
                    val channels = call.argument<Int>("channels")
                    val format = formats(device).firstOrNull { it.mixerBehavior == AudioMixerAttributes.MIXER_BEHAVIOR_BIT_PERFECT && it.format.sampleRate == rate && it.format.encoding == encoding && it.format.channelCount == channels }
                        ?: throw IllegalStateException("系统没有报告匹配的 Bit-Perfect 格式")
                    clearMixer()
                    if (!manager.setPreferredMixerAttributes(attributes, device, format)) throw IllegalStateException("系统拒绝启用 USB Bit-Perfect，设备可能正被占用")
                    mixerDevice = device
                    result.success(snapshot()); emit()
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) { result.error("audio_output", e.message ?: e.javaClass.simpleName, null) }
    }
    fun dispose() {
        closed = true
        clearMixer()
        if (deviceCallbackRegistered) try { manager.unregisterAudioDeviceCallback(callback) } catch (_: Exception) { }
        if (routerRegistered) try { router.removeCallback(routeCallback) } catch (_: Exception) { }
        if (Build.VERSION.SDK_INT >= 34) (mixerListener as? AudioManager.OnPreferredMixerAttributesChangedListener)?.let {
            try { manager.removeOnPreferredMixerAttributesChangedListener(it) } catch (_: Exception) { }
        }
        if (receiverRegistered) try { context.unregisterReceiver(identityReceiver) } catch (_: Exception) { }
        events.setStreamHandler(null); methods.setMethodCallHandler(null)
        sink = null
        if (active === this) active = null
        if (available) nativeDetach()
    }
}
