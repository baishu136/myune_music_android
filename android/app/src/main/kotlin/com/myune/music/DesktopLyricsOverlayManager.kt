package com.myune.music

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

class DesktopLyricsOverlayManager(
    private val context: Context,
    private val onEvent: (String, Map<String, Any?>) -> Unit,
) {
    private val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
    private var root: LinearLayout? = null
    private var params: WindowManager.LayoutParams? = null
    private var lyricView: TextView? = null
    private var controlsView: LinearLayout? = null
    private var styleView: LinearLayout? = null
    private var playButton: ImageButton? = null
    private var lockButton: ImageButton? = null
    private var expanded = false
    private var locked = false
    private var playing = false
    private var suppressed = false
    private var hasContent = false
    private var lyricColor = Color.rgb(0, 169, 214)
    private var lyricSize = 22f

    private val expandedBackgroundColor = Color.argb(77, 255, 255, 255)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val autoCollapseRunnable = Runnable {
        if (expanded && !locked) {
            collapseToLyricsOnly()
            applyVisualState(refreshWindow = true)
        }
    }

    fun showOrUpdate(values: Map<String, Any?>) {
        if (!Settings.canDrawOverlays(context)) return
        if (root == null) createOverlay()
        hasContent = true
        update(values)
        attachIfAllowed()
    }

    fun update(values: Map<String, Any?>) {
        val wasLocked = locked
        values["lyric"]?.let { lyricView?.text = it.toString() }
        values["isPlaying"]?.let { playing = it as? Boolean ?: playing }
        values["isLocked"]?.let { locked = it as? Boolean ?: locked }
        (values["color"] as? Number)?.let { lyricColor = it.toInt() }
        (values["fontSize"] as? Number)?.let { lyricSize = it.toFloat().coerceIn(16f, 38f) }
        applyVisualState(refreshWindow = wasLocked != locked)
    }

    fun hide() {
        hasContent = false
        cancelAutoCollapse()
        detach()
    }

    fun setSuppressed(value: Boolean) {
        if (suppressed == value) return
        suppressed = value
        if (value) {
            collapseToLyricsOnly()
            detach()
        } else {
            attachIfAllowed()
        }
    }

    fun setLocked(value: Boolean) {
        if (locked == value) return
        locked = value
        if (locked) collapseToLyricsOnly()
        applyVisualState(refreshWindow = true)
    }

    private fun collapseToLyricsOnly() {
        cancelAutoCollapse()
        expanded = false
        controlsView?.visibility = View.GONE
        styleView?.visibility = View.GONE
    }

    private fun scheduleAutoCollapse() {
        cancelAutoCollapse()
        if (expanded && !locked) {
            mainHandler.postDelayed(autoCollapseRunnable, AUTO_COLLAPSE_DELAY_MS)
        }
    }

    private fun cancelAutoCollapse() {
        mainHandler.removeCallbacks(autoCollapseRunnable)
    }

    private fun attachIfAllowed() {
        val view = root ?: return
        if (suppressed || !hasContent || view.parent != null || !Settings.canDrawOverlays(context)) {
            return
        }
        windowManager.addView(view, params)
    }

    private fun detach() {
        val view = root ?: return
        if (view.parent != null) windowManager.removeView(view)
    }

    private fun createOverlay() {
        val savedY = context.getSharedPreferences("desktop_lyrics", Context.MODE_PRIVATE)
            .getInt("overlay_y", dp(48))
        params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            } else {
                @Suppress("DEPRECATION")
                WindowManager.LayoutParams.TYPE_PHONE
            },
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            y = savedY
        }

        root = LinearLayout(context).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(8), dp(14), dp(8))
        }

        lyricView = TextView(context).apply {
            gravity = Gravity.CENTER
            maxLines = 3
            setTypeface(typeface, Typeface.NORMAL)
            setPadding(dp(8), dp(6), dp(8), dp(6))
            setShadowLayer(dp(1).toFloat(), 0f, dp(1).toFloat(), Color.argb(150, 0, 0, 0))
        }
        installDragAndExpand(lyricView!!)
        root!!.addView(lyricView, matchWrap())

        controlsView = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            addView(iconButton(R.drawable.ic_desktop_lyrics_app, "返回应用") {
                context.packageManager.getLaunchIntentForPackage(context.packageName)?.let {
                    it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    context.startActivity(it)
                }
            })
            lockButton = iconButton(R.drawable.ic_desktop_lyrics_lock, "锁定桌面歌词") {
                locked = true
                collapseToLyricsOnly()
                onEvent("locked", mapOf("locked" to true))
                applyVisualState(refreshWindow = true)
            }
            addView(lockButton)
            addView(iconButton(R.drawable.ic_desktop_lyrics_previous, "上一首") {
                onEvent("control", mapOf("action" to "previous"))
            })
            playButton = iconButton(R.drawable.ic_desktop_lyrics_play, "播放或暂停") {
                onEvent("control", mapOf("action" to "playPause"))
            }
            addView(playButton)
            addView(iconButton(R.drawable.ic_desktop_lyrics_next, "下一首") {
                onEvent("control", mapOf("action" to "next"))
            })
            addView(iconButton(R.drawable.ic_desktop_lyrics_tune, "桌面歌词设置") {
                styleView?.visibility = if (styleView?.visibility == View.VISIBLE) View.GONE else View.VISIBLE
                styleView?.requestLayout()
            })
            addView(iconButton(R.drawable.ic_desktop_lyrics_close, "关闭桌面歌词") {
                onEvent("close", emptyMap())
                hide()
            })
        }
        root!!.addView(controlsView, matchWrap())

        styleView = LinearLayout(context).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER
            visibility = View.GONE
            val colors = intArrayOf(
                Color.rgb(238, 22, 60),
                Color.rgb(0, 169, 214),
                Color.rgb(0, 199, 145),
                Color.rgb(229, 165, 13),
                Color.rgb(157, 67, 218),
            )
            colors.forEach { color ->
                addView(TextView(context).apply {
                    text = "●"
                    textSize = 30f
                    gravity = Gravity.CENTER
                    setTextColor(color)
                    contentDescription = "歌词颜色"
                    setPadding(dp(7), 0, dp(7), 0)
                    setOnClickListener {
                        scheduleAutoCollapse()
                        lyricColor = color
                        onEvent("style", mapOf("color" to color, "fontSize" to lyricSize.toDouble()))
                        applyVisualState()
                    }
                })
            }
            addView(textButton("T+") {
                lyricSize = (lyricSize + 2f).coerceAtMost(38f)
                onEvent("style", mapOf("color" to lyricColor, "fontSize" to lyricSize.toDouble()))
                applyVisualState()
            })
            addView(textButton("T−") {
                lyricSize = (lyricSize - 2f).coerceAtLeast(16f)
                onEvent("style", mapOf("color" to lyricColor, "fontSize" to lyricSize.toDouble()))
                applyVisualState()
            })
        }
        root!!.addView(styleView, matchWrap())
    }

    private fun installDragAndExpand(view: View) {
        var startRawY = 0f
        var startWindowY = 0
        var dragged = false
        view.setOnTouchListener { _, event ->
            if (locked) return@setOnTouchListener false
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    cancelAutoCollapse()
                    startRawY = event.rawY
                    startWindowY = params?.y ?: 0
                    dragged = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val delta = event.rawY - startRawY
                    if (abs(delta) > dp(6).toFloat()) dragged = true
                    if (dragged) {
                        params?.y = (startWindowY + delta.toInt()).coerceAtLeast(0)
                        refreshLayout()
                    }
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (dragged) {
                        context.getSharedPreferences("desktop_lyrics", Context.MODE_PRIVATE)
                            .edit().putInt("overlay_y", params?.y ?: 0).apply()
                        scheduleAutoCollapse()
                    } else {
                        expanded = !expanded
                        controlsView?.visibility = if (expanded) View.VISIBLE else View.GONE
                        if (!expanded) styleView?.visibility = View.GONE
                        applyVisualState()
                        scheduleAutoCollapse()
                    }
                    true
                }
                MotionEvent.ACTION_CANCEL -> {
                    scheduleAutoCollapse()
                    true
                }
                else -> false
            }
        }
    }

    private fun applyVisualState(refreshWindow: Boolean = false) {
        lyricView?.setTextColor(lyricColor)
        lyricView?.textSize = lyricSize
        playButton?.setImageResource(
            if (playing) R.drawable.ic_desktop_lyrics_pause else R.drawable.ic_desktop_lyrics_play,
        )
        root?.background = if (expanded) {
            roundedBackground(expandedBackgroundColor)
        } else {
            null
        }
        params?.let { lp ->
            val base = WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN
            var flags = if (locked) {
                base or WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE
            } else {
                base
            }
            lp.flags = flags
        }
        if (refreshWindow) refreshLayout()
    }

    private fun refreshLayout() {
        val view = root ?: return
        if (view.parent != null) windowManager.updateViewLayout(view, params)
    }

    private fun iconButton(icon: Int, description: String, action: () -> Unit) =
        ImageButton(context).apply {
            setImageResource(icon)
            contentDescription = description
            setColorFilter(Color.rgb(205, 211, 226))
            scaleType = ImageView.ScaleType.CENTER_INSIDE
            setPadding(dp(12), dp(10), dp(12), dp(10))
            val typedValue = TypedValue()
            if (context.theme.resolveAttribute(
                    android.R.attr.selectableItemBackgroundBorderless,
                    typedValue,
                    true,
                )
            ) {
                setBackgroundResource(typedValue.resourceId)
            } else {
                background = null
            }
            setOnClickListener {
                scheduleAutoCollapse()
                action()
            }
            layoutParams = LinearLayout.LayoutParams(0, dp(48), 1f)
        }

    private fun textButton(label: String, action: () -> Unit) = TextView(context).apply {
        text = label
        textSize = 22f
        gravity = Gravity.CENTER
        setTextColor(Color.rgb(205, 211, 226))
        setTypeface(typeface, Typeface.BOLD)
        setPadding(dp(10), dp(5), dp(10), dp(5))
        setOnClickListener {
            scheduleAutoCollapse()
            action()
        }
    }

    private fun roundedBackground(color: Int) = GradientDrawable().apply {
        setColor(color)
        cornerRadius = dp(20).toFloat()
    }

    private fun matchWrap() = LinearLayout.LayoutParams(
        LinearLayout.LayoutParams.MATCH_PARENT,
        LinearLayout.LayoutParams.WRAP_CONTENT,
    )

    private fun dp(value: Int): Int = (value * context.resources.displayMetrics.density).toInt()

    private companion object {
        const val AUTO_COLLAPSE_DELAY_MS = 6_000L
    }
}
