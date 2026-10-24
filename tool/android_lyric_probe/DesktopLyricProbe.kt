package com.myune.music

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.RectF
import android.graphics.RenderNode
import android.graphics.Typeface
import android.os.Bundle
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import android.icu.text.BreakIterator

/** Standalone SDK probe: compiles the actual production views, never the player. */
class DesktopLyricProbe : Activity() {
    private val results = JSONArray()

    override fun onCreate(state: Bundle?) {
        super.onCreate(state)
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setBackgroundColor(Color.rgb(25, 25, 30))
            setPadding(24, 80, 24, 24)
        }
        val cases = listOf(
            Triple("wrap-center", "one two three four five six seven eight nine ten", false),
            Triple("wrap-left", "第一行歌词持续播放直到自动折行结束以及后续文字", false),
            Triple("bidi-right", "Hello مرحبا بالعالم 世界 together", false),
            Triple("fit-center", "A very long lyric 👨‍👩‍👦 with é and music\n短译文", true),
            Triple("ellipsis-center", "一二三四五六七八九十".repeat(9), false),
        )
        for ((name, text, fit) in cases) {
            val result = JSONObject().put("name", name)
            try {
                val view = OutlinedLyricTextView(this).apply {
                    includeFontPadding = false
                    setPadding(12, 8, 12, 8)
                    configure(Color.WHITE, 22f, Typeface.DEFAULT, fit,
                        name.substringAfter('-'), true, 1f, Color.BLACK, 1f)
                }
                val iterator = BreakIterator.getCharacterInstance().apply { setText(text) }
                val tokens = ArrayList<Map<String, Any>>()
                var offset = 0
                var i = 0
                while (offset < text.length) {
                    val end = iterator.following(offset)
                    tokens.add(mapOf("offset" to offset, "length" to end - offset,
                        "start" to i * 1000, "end" to (i + 1) * 1000))
                    i++
                    offset = end
                }
                fun payload(position: Int) = mapOf("lyric" to text, "words" to tokens,
                    "lyricKey" to name, "karaoke" to true, "highlightColor" to Color.CYAN,
                    "positionMs" to position, "isPlaying" to false, "playbackRate" to 1.0)
                view.updatePlayback(payload(1500))
                view.measure(View.MeasureSpec.makeMeasureSpec(480, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(1800, View.MeasureSpec.AT_MOST))
                view.layout(0, 0, view.measuredWidth, view.measuredHeight)
                val field = view.javaClass.getDeclaredField("cells").apply { isAccessible = true }
                val cells = field.get(view) as List<*>
                var invalid = 0
                for (cell in cells) {
                    val box = cell!!.javaClass.getDeclaredField("box").apply { isAccessible = true }.get(cell) as RectF
                    val start = cell.javaClass.getDeclaredField("start").apply { isAccessible = true }.getDouble(cell)
                    val token = tokens[(start / 1000).toInt()]
                    val at = token["offset"] as Int
                    val line = view.layout.getLineForOffset(at)
                    val lineTop = view.layout.getLineTop(line).toFloat()
                    val lineBottom = view.layout.getLineBottom(line).toFloat()
                    val hiddenStart = view.layout.getLineStart(line) + view.layout.getEllipsisStart(line)
                    val hiddenEnd = hiddenStart + view.layout.getEllipsisCount(line)
                    if (line >= view.maxLines || box.top < lineTop - .01 || box.bottom > lineBottom + .01 ||
                        (at >= hiddenStart && at < hiddenEnd)) invalid++
                }
                result.put("cells", cells.size).put("invalidGeometry", invalid)
                check(cells.isNotEmpty() && invalid == 0) { "Cross-line or hidden highlight cells: $invalid" }
                val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                view.draw(Canvas(bitmap))
                File(getExternalFilesDir(null), "$name.png").outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
                if (android.os.Build.VERSION.SDK_INT >= 29) {
                    val node = RenderNode("probe")
                    node.setPosition(0, 0, view.width, view.height)
                    view.draw(node.beginRecording())
                    node.endRecording()
                    val cacheField = runCatching {
                        view.javaClass.getDeclaredField("textCache").apply { isAccessible = true }
                    }.getOrNull()
                    val cache = cacheField?.get(view)
                    if (cacheField != null) check(cache != null)
                    val startTime = System.nanoTime()
                    repeat(120) { frame ->
                        if (cacheField != null) view.updatePlayback(mapOf("clockOnly" to true, "lyricKey" to name,
                            "positionMs" to 1500 + frame * 16, "isPlaying" to false, "playbackRate" to 1.0))
                        view.draw(node.beginRecording())
                        node.endRecording()
                        if (cacheField != null) check(cacheField.get(view) === cache)
                        check(field.get(view) === cells)
                    }
                    result.put("record120ms", (System.nanoTime() - startTime) / 1e6)
                    result.put("cacheAndGeometryReused", cacheField != null)
                }
                view.updatePlayback(payload(1500))
                root.addView(view, LinearLayout.LayoutParams(-1, -2))
                result.put("passed", true)
            } catch (error: Throwable) {
                result.put("passed", false).put("error", error.toString())
            }
            results.put(result)
        }
        File(getExternalFilesDir(null), "results.json").writeText(results.toString(2))
        root.addView(TextView(this).apply { setTextColor(Color.YELLOW); text = results.toString(2) })
        setContentView(root)
    }
}
