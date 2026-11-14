package com.myune.music

import android.app.Service
import android.content.Intent
import android.os.*

/** Permissionless OS process. All JS/native work stays off the player/UI threads. */
class PluginScriptService : Service() {
    private lateinit var worker: HandlerThread
    private lateinit var messenger: Messenger
    private lateinit var bootstrap: ByteArray
    private external fun nativeRun(op: Int, code: ByteArray, boot: ByteArray, input: ByteArray): ByteArray

    override fun onCreate() {
        super.onCreate()
        System.loadLibrary("myune_plugin_js")
        bootstrap = assets.open("myune_plugin_bootstrap.js").use { it.readBytes() }
        worker = HandlerThread("myune-plugin-js").also { it.start() }
        messenger = Messenger(Handler(worker.looper) { message ->
            val reply = Bundle()
            try {
                val data = message.data
                val op = data.getInt("op")
                val code = data.getString("code", "").toByteArray(Charsets.UTF_8)
                val input = data.getString("input", "null").toByteArray(Charsets.UTF_8)
                require(code.size <= 131072 && input.size <= 196608 && op in 0..2)
                val result = nativeRun(op, code, bootstrap, input)
                reply.putString("result", result.toString(Charsets.UTF_8))
                reply.putInt("uid", Process.myUid())
                reply.putInt("pid", Process.myPid())
                reply.putBoolean("isolated", if (Build.VERSION.SDK_INT >= 28) Process.isIsolated() else Process.myUid() % 100000 >= 99000)
            } catch (failure: Throwable) {
                reply.putString("error", failure.javaClass.simpleName)
            }
            try {
                message.replyTo?.send(Message.obtain(null, message.what).also { it.data = reply })
            } catch (_: RemoteException) { /* Host unbound. No player state is owned here. */ }
            true
        })
    }
    override fun onBind(intent: Intent): IBinder = messenger.binder
    override fun onDestroy() {
        Handler(worker.looper).post { nativeRun(2, byteArrayOf(), bootstrap, byteArrayOf()) }
        worker.quitSafely()
        super.onDestroy()
    }
}
