package com.myune.music

import android.content.Context
import android.os.Build
import android.os.Process
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Minimal process-start logger. It deliberately uses only Context.filesDir so
 * it is independent of storage permissions, scoped storage, Flutter, and all
 * third-party SDKs.
 */
object FaultLogWriter {
    private const val reportDirectoryName = "myune fault log"
    private const val startupTraceName = "startup_trace.txt"
    private val lock = Any()
    @Volatile private var installed = false
    @Volatile private var internalDirectory: File? = null

    fun install(context: Context) {
        synchronized(lock) {
            if (installed) return
            installed = true
            val previous = Thread.getDefaultUncaughtExceptionHandler()
            Thread.setDefaultUncaughtExceptionHandler { thread, error ->
                try {
                    writeNativeCrash(context, thread, error)
                } catch (_: Throwable) {
                    // Never replace the original crash with a logger failure.
                } finally {
                    if (previous != null) {
                        previous.uncaughtException(thread, error)
                    } else {
                        Process.killProcess(Process.myPid())
                    }
                }
            }
            appendBreadcrumbLocked(context, "BOOT_01 process/application created")
            appendBreadcrumbLocked(context, "BOOT_02 Application.attachBaseContext")
            internalDirectory = prepareInternalDirectory(context)
            appendBreadcrumbLocked(context, "BOOT_03 crash handler installed")
        }
    }

    fun breadcrumb(context: Context, marker: String) {
        synchronized(lock) {
            appendBreadcrumbLocked(context, marker)
        }
    }

    /** Returns the permission-free internal directory used by Flutter too. */
    fun resolveDirectory(context: Context): File {
        synchronized(lock) {
            val existing = internalDirectory
            if (existing != null) return existing
            val prepared = prepareInternalDirectory(context)
            internalDirectory = prepared
            return prepared
        }
    }

    private fun prepareInternalDirectory(context: Context): File {
        val directory = try {
            File(context.filesDir, reportDirectoryName)
        } catch (_: Throwable) {
            // filesDir is expected to be available from attachBaseContext. The
            // cache fallback is still app-private and permission-free.
            File(context.cacheDir, reportDirectoryName)
        }
        try {
            directory.mkdirs()
        } catch (_: Throwable) {
            // The crash handler will make one final best-effort write.
        }
        return directory
    }

    private fun appendBreadcrumbLocked(context: Context, marker: String) {
        val line = try {
            "${nowText()} [$pid] [${Thread.currentThread().name}] $marker\n"
        } catch (_: Throwable) {
            return
        }
        try {
            val directory = internalDirectory ?: prepareInternalDirectory(context)
            internalDirectory = directory
            val trace = File(directory, startupTraceName)
            trace.parentFile?.mkdirs()
            trace.appendText(line)
        } catch (_: Throwable) {
            // Breadcrumbs are diagnostic only and must never affect startup.
        }
    }

    private fun writeNativeCrash(context: Context, thread: Thread, error: Throwable) {
        synchronized(lock) {
            val now = Date()
            val root = internalDirectory ?: prepareInternalDirectory(context)
            internalDirectory = root
            val dateFolder = SimpleDateFormat("yy.M.d", Locale.US).format(now)
            val timeName = SimpleDateFormat("HH.mm.ss.SSS", Locale.US).format(now)
            val directory = File(root, dateFolder).apply { mkdirs() }
            var file = File(directory, "$timeName.log")
            var collision = 1
            while (file.exists()) {
                file = File(directory, "${timeName}_${collision++}.log")
            }
            file.bufferedWriter().use { writer ->
                writer.appendLine("Myune Music fault report")
                writer.appendLine("Timestamp: ${SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(now)}")
                writer.appendLine("Source: Android native uncaught exception")
                writer.appendLine("Thread: ${thread.name} (${thread.id})")
                writer.appendLine("Android: ${Build.VERSION.RELEASE} (SDK ${Build.VERSION.SDK_INT})")
                writer.appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}")
                writer.appendLine("Process ID: ${Process.myPid()}")
                writer.appendLine("Internal log directory: ${root.absolutePath}")
                writer.appendLine()
                writer.appendLine("Exception type: ${error.javaClass.name}")
                writer.appendLine("Exception: ${error.message ?: error.toString()}")
                writer.appendLine()
                writer.appendLine("Stack trace:")
                writer.appendLine(error.stackTraceToString())
            }
        }
    }

    private fun nowText(): String =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).format(Date())

    private val pid: Int
        get() = Process.myPid()
}
