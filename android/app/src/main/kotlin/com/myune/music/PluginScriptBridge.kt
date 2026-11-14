package com.myune.music

import android.content.*
import android.os.*
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class PluginScriptBridge(private val context: Context, binary: BinaryMessenger) {
    private val handler = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(binary, "com.myune.music/plugins")
    private val pending = linkedMapOf<Int, Pair<Bundle, MethodChannel.Result>>()
    private var remote: Messenger? = null
    private var bound = false
    private var serial = 0
    private var disposed = false
    private val replies = Messenger(Handler(Looper.getMainLooper()) { message ->
        val entry = pending.remove(message.what)
        if (entry != null) {
            val error = message.data.getString("error")
            if (error != null) entry.second.error("plugin_runtime", error, null)
            else entry.second.success(mapOf(
                "result" to message.data.getString("result"),
                "uid" to message.data.getInt("uid"), "pid" to message.data.getInt("pid"),
                "isolated" to message.data.getBoolean("isolated"), "hostUid" to Process.myUid()))
        }
        releaseIfIdle()
        true
    })
    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            if (disposed) return
            remote = Messenger(service)
            pending.toMap().forEach { (id, entry) -> send(id, entry.first) }
        }
        override fun onServiceDisconnected(name: ComponentName) = reset("Plugin process disconnected")
        override fun onBindingDied(name: ComponentName) = reset("Plugin binding died")
        override fun onNullBinding(name: ComponentName) = reset("Plugin binding unavailable")
    }
    init {
        channel.setMethodCallHandler { call, result ->
            if (disposed || call.method !in listOf("start", "step", "close")) {
                result.error("plugin_runtime", "Runtime unavailable", null)
            } else {
                val code = call.argument<String>("code") ?: ""
                val input = call.argument<String>("input") ?: "null"
                if (code.toByteArray().size > 131072 || input.toByteArray().size > 196608 || pending.size >= 2) {
                    result.error("plugin_runtime", "Request limit", null)
                } else {
                    handler.removeCallbacks(idleRelease)
                    val id = ++serial
                    val data = Bundle().apply {
                        putInt("op", when(call.method) { "start" -> 0; "step" -> 1; else -> 2 })
                        putString("code", code); putString("input", input)
                    }
                    pending[id] = data to result
                    if (!bound) {
                        try {
                            bound = context.bindService(Intent(context, PluginScriptService::class.java), connection, Context.BIND_AUTO_CREATE)
                            if (!bound) reset("Cannot bind plugin process")
                        } catch (_: Exception) { reset("Cannot bind plugin process") }
                    } else if (remote != null) send(id, data)
                    handler.postDelayed({ if (pending.containsKey(id)) reset("Plugin response timed out") }, 4000)
                }
            }
        }
    }
    private fun send(id: Int, data: Bundle) {
        try { remote?.send(Message.obtain(null, id).also { it.data = data; it.replyTo = replies }) }
        catch (_: RemoteException) { reset("Plugin transport failed") }
    }
    private val idleRelease = Runnable { if (pending.isEmpty()) unbind() }
    private fun releaseIfIdle() { if (pending.isEmpty()) handler.postDelayed(idleRelease, 30000) }
    private fun unbind() {
        remote = null
        if (bound) { bound = false; try { context.unbindService(connection) } catch (_: Exception) {} }
    }
    private fun reset(reason: String) {
        val entries = pending.values.toList(); pending.clear(); unbind()
        entries.forEach { it.second.error("plugin_runtime", reason, null) }
    }
    fun dispose() {
        disposed = true; channel.setMethodCallHandler(null)
        handler.removeCallbacksAndMessages(null); reset("Player closed")
    }
}
