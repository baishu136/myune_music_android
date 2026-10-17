package com.myune.music

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.icu.text.BreakIterator
import android.os.SystemClock
import android.text.SpannableString
import android.text.Spanned
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.MetricAffectingSpan
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.TextView

/** Layout/word geometry changes only with content, width or style, never a frame. */
internal class OutlinedLyricTextView(context: Context) : TextView(context) {
    private var rawText = ""
    private var fillColor = Color.WHITE
    private var outlineEnabled = false
    private var outlineWidth = 0f
    private var outlineColor = Color.WHITE
    private var autoFit = false
    private var layoutDirty = true
    private var geometryDirty = true
    private var configuredPx = textSize
    private var lastWidth = -1
    private var words = emptyList<DesktopLyricWord>()
    private val clock = DesktopLyricClock()
    private var karaoke = false
    private var highlightColor = Color.WHITE
    private val highlightPath = Path()
    private data class Cell(val box: RectF, val start: Double, val end: Double, val rtl: Boolean)
    private var cells = emptyList<Cell>()

    fun configure(
        color: Int, size: Float, face: Typeface, autoSize: Boolean, alignment: String,
        stroke: Boolean, strokeWidth: Float, strokeColor: Int, strokeOpacity: Float,
    ) {
        val px = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, size,
            resources.displayMetrics)
        val width = strokeWidth.coerceIn(0.5f, 4f) * resources.displayMetrics.density
        if (configuredPx != px || typeface != face || autoFit != autoSize ||
            outlineEnabled != stroke || outlineWidth != width) layoutDirty = true
        configuredPx = px
        if (typeface != face) typeface = face
        autoFit = autoSize
        outlineEnabled = stroke
        outlineWidth = width
        outlineColor = Color.argb((Color.alpha(strokeColor) * strokeOpacity.coerceIn(.1f, 1f)).toInt(),
            Color.red(strokeColor), Color.green(strokeColor), Color.blue(strokeColor))
        fillColor = color
        if (currentTextColor != color) setTextColor(color)
        val nextGravity = Gravity.TOP or when (alignment) {
            "left" -> Gravity.LEFT
            "right" -> Gravity.RIGHT
            else -> Gravity.CENTER_HORIZONTAL
        }
        if (gravity != nextGravity) { gravity = nextGravity; geometryDirty = true }
        if (layoutDirty) requestLayout()
        invalidate()
    }

    fun updatePlayback(values: Map<String, Any?>) {
        val incoming = values["lyric"]?.toString() ?: rawText
        if (incoming != rawText) {
            rawText = incoming
            layoutDirty = true
            requestLayout()
        }
        val incomingWords = (values["words"] as? List<*>)?.mapNotNull { entry ->
            val w = entry as? Map<*, *> ?: return@mapNotNull null
            val offset = (w["offset"] as? Number)?.toInt() ?: return@mapNotNull null
            val length = (w["length"] as? Number)?.toInt() ?: return@mapNotNull null
            val start = (w["start"] as? Number)?.toDouble() ?: return@mapNotNull null
            val end = (w["end"] as? Number)?.toDouble() ?: return@mapNotNull null
            if (offset < 0 || length <= 0 || offset.toLong() + length > incoming.length ||
                !start.isFinite() || !end.isFinite() || start < 0 || end < start) null
            else DesktopLyricWord(offset, length, start, end)
        } ?: emptyList()
        if (words != incomingWords) { words = incomingWords; geometryDirty = true }
        karaoke = values["karaoke"] == true
        highlightColor = (values["highlightColor"] as? Number)?.toInt() ?: fillColor
        clock.update(values["lyricKey"]?.toString().orEmpty(),
            (values["positionMs"] as? Number)?.toDouble() ?: 0.0,
            values["isPlaying"] == true,
            (values["playbackRate"] as? Number)?.toDouble() ?: 1.0,
            SystemClock.uptimeMillis())
        invalidate()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val contentWidth = MeasureSpec.getSize(widthMeasureSpec) - compoundPaddingLeft - compoundPaddingRight
        if (layoutDirty || lastWidth != contentWidth) {
            lastWidth = contentWidth
            setTextSize(TypedValue.COMPLEX_UNIT_PX, configuredPx)
            maxLines = if (autoFit) Int.MAX_VALUE else 3
            ellipsize = if (autoFit) null else TextUtils.TruncateAt.END
            val styled = SpannableString(rawText)
            if (autoFit && contentWidth > 0) {
                val measurePaint = TextPaint(paint)
                val available = (contentWidth - (if (outlineEnabled) outlineWidth * 2 else 0f) - 2f).coerceAtLeast(1f)
                var start = 0
                rawText.split('\n').forEach { row ->
                    if (row.isNotEmpty()) {
                        val fitted = fitDesktopLyricSize(configuredPx, available) { size ->
                            measurePaint.textSize = size
                            measurePaint.measureText(row)
                        }
                        if (fitted < configuredPx) styled.setSpan(FloatSize(fitted), start,
                            start + row.length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                    }
                    start += row.length + 1
                }
            }
            text = styled
            scrollTo(0, 0)
            layoutDirty = false
            geometryDirty = true
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        scrollTo(0, 0)
        if (changed) geometryDirty = true
        if (geometryDirty) rebuildCells()
    }

    private fun rebuildCells() {
        val textLayout = layout ?: return
        val result = ArrayList<Cell>()
        val iterator = BreakIterator.getCharacterInstance().apply { setText(rawText) }
        val selection = Path()
        for (word in words) {
            val boxes = ArrayList<Pair<RectF, Boolean>>()
            var offset = word.offset
            val limit = word.offset + word.length
            while (offset < limit) {
                val next = iterator.following(offset).let { if (it == BreakIterator.DONE) limit else minOf(it, limit) }
                if (rawText.substring(offset, next) != "\n") {
                    selection.rewind()
                    textLayout.getSelectionPath(offset, next, selection)
                    val box = RectF()
                    selection.computeBounds(box, true)
                    if (!box.isEmpty) boxes.add(box to textLayout.isRtlCharAt(offset))
                }
                offset = next
            }
            val total = boxes.sumOf { it.first.width().toDouble() }
            var travelled = 0.0
            for ((box, rtl) in boxes) {
                val start = word.start + (word.end - word.start) * travelled / total
                travelled += box.width()
                val end = word.start + (word.end - word.start) * travelled / total
                result.add(Cell(box, start, end, rtl))
            }
        }
        cells = result
        geometryDirty = false
    }

    override fun onDraw(canvas: Canvas) {
        val textLayout = layout ?: return
        if (geometryDirty) rebuildCells()
        val save = canvas.save()
        // Padding protects outlines, accents and both edges during fitting.
        canvas.clipRect(0, 0, width, height)
        canvas.translate(compoundPaddingLeft.toFloat(), extendedPaddingTop.toFloat())
        if (outlineEnabled) {
            paint.style = Paint.Style.STROKE
            paint.strokeWidth = outlineWidth
            paint.strokeJoin = Paint.Join.ROUND
            paint.color = outlineColor
            textLayout.draw(canvas)
        }
        paint.style = Paint.Style.FILL
        paint.color = fillColor
        textLayout.draw(canvas)
        val position = clock.position(SystemClock.uptimeMillis())
        if (karaoke && cells.isNotEmpty()) {
            highlightPath.rewind()
            for (cell in cells) {
                val progress = when {
                    position < cell.start -> 0f
                    position >= cell.end || cell.end <= cell.start -> 1f
                    else -> ((position - cell.start) / (cell.end - cell.start)).toFloat()
                }
                if (progress > 0f) {
                    val b = cell.box
                    val extent = b.width() * progress
                    highlightPath.addRect(if (cell.rtl) b.right - extent else b.left,
                        b.top - 2f, if (cell.rtl) b.right else b.left + extent, b.bottom + 2f, Path.Direction.CW)
                }
            }
            canvas.save()
            canvas.clipPath(highlightPath)
            paint.color = highlightColor
            textLayout.draw(canvas)
            canvas.restore()
            paint.color = fillColor
            if (clock.playing && isAttachedToWindow && windowVisibility == View.VISIBLE &&
                cells.any { position < it.end }) postInvalidateOnAnimation()
        }
        canvas.restoreToCount(save)
    }

    private class FloatSize(private val size: Float) : MetricAffectingSpan() {
        override fun updateDrawState(paint: TextPaint) { paint.textSize = size }
        override fun updateMeasureState(paint: TextPaint) { paint.textSize = size }
    }
}
