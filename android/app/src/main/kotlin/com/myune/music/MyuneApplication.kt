package com.myune.music

import android.content.Context
import io.flutter.app.FlutterApplication

class MyuneApplication : FlutterApplication() {
    override fun attachBaseContext(base: Context) {
        if (!isPluginIsolatedProcess()) FaultLogWriter.install(base)
        super.attachBaseContext(base)
    }

    override fun onCreate() {
        super.onCreate()
        if (!isPluginIsolatedProcess()) FaultLogWriter.breadcrumb(this, "BOOT_04 Application.onCreate")
    }

    private fun isPluginIsolatedProcess(): Boolean =
        if (android.os.Build.VERSION.SDK_INT >= 28) android.os.Process.isIsolated()
        else android.os.Process.myUid() % 100000 >= 99000
}
