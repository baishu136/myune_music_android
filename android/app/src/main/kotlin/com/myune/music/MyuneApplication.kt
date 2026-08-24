package com.myune.music

import android.content.Context
import io.flutter.app.FlutterApplication

class MyuneApplication : FlutterApplication() {
    override fun attachBaseContext(base: Context) {
        FaultLogWriter.install(base)
        super.attachBaseContext(base)
    }

    override fun onCreate() {
        super.onCreate()
        FaultLogWriter.breadcrumb(this, "BOOT_04 Application.onCreate")
    }
}
