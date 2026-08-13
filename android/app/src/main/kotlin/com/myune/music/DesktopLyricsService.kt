package com.myune.music

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper

/**
 * Owns the desktop-lyrics window independently from MainActivity.
 *
 * Playback already keeps this process alive through its media playback
 * foreground service, so this service deliberately does not create a second
 * persistent notification. Moving the WindowManager owner here prevents the
 * overlay from disappearing or leaking when MainActivity is recreated.
 */
class DesktopLyricsService : Service() {
    private lateinit var overlay: DesktopLyricsOverlayManager
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreate() {
        super.onCreate()
        instance = this
        overlay = DesktopLyricsOverlayManager(applicationContext) { type, payload ->
            eventSink?.invoke(type, payload)
        }
        overlay.setSuppressed(appVisible)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_SHOW -> overlay.showOrUpdate(intent.toOverlayValues())
            ACTION_HIDE -> {
                overlay.hide()
                stopSelf()
            }
            ACTION_LOCK -> overlay.setLocked(intent.getBooleanExtra(EXTRA_LOCKED, false))
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        overlay.hide()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun applyOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) action() else mainHandler.post(action)
    }

    companion object {
        private const val ACTION_SHOW = "com.myune.music.desktoplyrics.SHOW"
        private const val ACTION_HIDE = "com.myune.music.desktoplyrics.HIDE"
        private const val ACTION_LOCK = "com.myune.music.desktoplyrics.LOCK"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_ARTIST = "artist"
        private const val EXTRA_LYRIC = "lyric"
        private const val EXTRA_PLAYING = "isPlaying"
        private const val EXTRA_LOCKED = "isLocked"
        private const val EXTRA_COLOR = "color"
        private const val EXTRA_FONT_SIZE = "fontSize"
        private const val EXTRA_DYNAMIC_COLOR = "dynamicColor"

        @Volatile
        private var instance: DesktopLyricsService? = null

        @Volatile
        private var eventSink: ((String, Map<String, Any?>) -> Unit)? = null

        @Volatile
        private var appVisible = false

        fun setEventSink(value: ((String, Map<String, Any?>) -> Unit)?) {
            eventSink = value
        }

        /**
         * The setting remains enabled while MainActivity is visible, but the
         * overlay is detached so it never covers the player itself. Leaving
         * the app attaches the existing view again without rebuilding it.
         */
        fun setAppVisible(visible: Boolean) {
            appVisible = visible
            instance?.let { service ->
                service.applyOnMain { service.overlay.setSuppressed(visible) }
            }
        }

        fun showOrUpdate(context: Context, values: Map<String, Any?>) {
            instance?.let { service ->
                service.applyOnMain { service.overlay.showOrUpdate(values) }
                return
            }
            val intent = Intent(context, DesktopLyricsService::class.java)
                .setAction(ACTION_SHOW)
                .putOverlayValues(values)
            // The first enable action is initiated while the settings Activity is
            // foreground, so a regular service start is allowed. Later updates use
            // the live instance directly and never repeatedly start a service.
            context.startService(intent)
        }

        fun hide(context: Context) {
            instance?.let { service ->
                service.applyOnMain {
                    service.overlay.hide()
                    service.stopSelf()
                }
                return
            }
            context.stopService(Intent(context, DesktopLyricsService::class.java))
        }

        fun setLocked(context: Context, locked: Boolean) {
            instance?.let { service ->
                service.applyOnMain { service.overlay.setLocked(locked) }
                return
            }
            context.startService(
                Intent(context, DesktopLyricsService::class.java)
                    .setAction(ACTION_LOCK)
                    .putExtra(EXTRA_LOCKED, locked),
            )
        }

        private fun Intent.putOverlayValues(values: Map<String, Any?>): Intent = apply {
            putExtra(EXTRA_TITLE, values[EXTRA_TITLE]?.toString().orEmpty())
            putExtra(EXTRA_ARTIST, values[EXTRA_ARTIST]?.toString().orEmpty())
            putExtra(EXTRA_LYRIC, values[EXTRA_LYRIC]?.toString().orEmpty())
            putExtra(EXTRA_PLAYING, values[EXTRA_PLAYING] as? Boolean ?: false)
            putExtra(EXTRA_LOCKED, values[EXTRA_LOCKED] as? Boolean ?: false)
            putExtra(EXTRA_COLOR, (values[EXTRA_COLOR] as? Number)?.toInt() ?: 0xFF00A9D6.toInt())
            putExtra(EXTRA_FONT_SIZE, (values[EXTRA_FONT_SIZE] as? Number)?.toFloat() ?: 22f)
            putExtra(EXTRA_DYNAMIC_COLOR, values[EXTRA_DYNAMIC_COLOR] as? Boolean ?: false)
        }

        private fun Intent.toOverlayValues(): Map<String, Any?> = mapOf(
            EXTRA_TITLE to getStringExtra(EXTRA_TITLE).orEmpty(),
            EXTRA_ARTIST to getStringExtra(EXTRA_ARTIST).orEmpty(),
            EXTRA_LYRIC to getStringExtra(EXTRA_LYRIC).orEmpty(),
            EXTRA_PLAYING to getBooleanExtra(EXTRA_PLAYING, false),
            EXTRA_LOCKED to getBooleanExtra(EXTRA_LOCKED, false),
            EXTRA_COLOR to getIntExtra(EXTRA_COLOR, 0xFF00A9D6.toInt()),
            EXTRA_FONT_SIZE to getFloatExtra(EXTRA_FONT_SIZE, 22f),
            EXTRA_DYNAMIC_COLOR to getBooleanExtra(EXTRA_DYNAMIC_COLOR, false),
        )
    }
}
