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
import android.os.Build
import android.text.StaticLayout
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
    private var fittedMaxLines = 3
    private var minimumPx = 12f
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
    private var visibleWords = emptyList<DesktopLyricWord>()
    private var textCache: TextCache? = null
    private var drawingDirty = true
    private val nextFrame = Runnable { invalidate() }

    fun configure(
        color: Int, size: Float, face: Typeface, autoSize: Boolean, alignment: String,
        stroke: Boolean, strokeWidth: Float, strokeColor: Int, strokeOpacity: Float,
        maximumLines: Int = 3, minimumSize: Float = 12f,
    ) {
        drawingDirty = true
        val px = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, size,
            resources.displayMetrics)
        val width = strokeWidth.coerceIn(0.5f, 4f) * resources.displayMetrics.density
        val minimum = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, minimumSize,
            resources.displayMetrics).coerceAtMost(px)
        val lines = maximumLines.coerceIn(1, 6)
        if (configuredPx != px || typeface != face || autoFit != autoSize ||
            fittedMaxLines != lines || minimumPx != minimum ||
            outlineEnabled != stroke || outlineWidth != width) layoutDirty = true
        configuredPx = px
        minimumPx = minimum
        fittedMaxLines = lines
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
        removeCallbacks(nextFrame)
        val incoming = values["lyric"]?.toString() ?: rawText
        if (incoming != rawText) {
            rawText = incoming
            layoutDirty = true
            requestLayout()
        }
        if (values.containsKey("words")) {
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
        }
        (values["karaoke"] as? Boolean)?.let { karaoke = it }
        (values["highlightColor"] as? Number)?.toInt()?.let {
            if (highlightColor != it) drawingDirty = true
            highlightColor = it
        }
        clock.update((values["timelineKey"] ?: values["lyricKey"])?.toString().orEmpty(),
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
            maxLines = if (autoFit) fittedMaxLines else 3
            ellipsize = TextUtils.TruncateAt.END
            if (autoFit && contentWidth > 0) {
                val measurePaint = TextPaint(paint)
                val available = (contentWidth - (if (outlineEnabled) outlineWidth * 2 else 0f) - 2f).coerceAtLeast(1f)
                val fitted = fitDesktopLyricMultilineSize(configuredPx, minimumPx) { size ->
                    measurePaint.textSize = size
                    val sample = StaticLayout.Builder.obtain(rawText, 0, rawText.length,
                        measurePaint, available.toInt().coerceAtLeast(1))
                        .setIncludePad(false).setBreakStrategy(breakStrategy)
                        .setHyphenationFrequency(hyphenationFrequency).build()
                    sample.lineCount <= fittedMaxLines
                }
                setTextSize(TypedValue.COMPLEX_UNIT_PX, fitted)
            }
            text = rawText
            scrollTo(0, 0)
            layoutDirty = false
            geometryDirty = true
        }
        super.onMeasure(widthMeasureSpec, heightMeasureSpec)
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        super.onLayout(changed, left, top, right, bottom)
        scrollTo(0, 0)
        if (changed) { geometryDirty = true; drawingDirty = true }
        if (geometryDirty) rebuildCells()
    }

    private fun rebuildCells() {
        val textLayout = layout ?: return
        val result = ArrayList<Cell>()
        val iterator = BreakIterator.getCharacterInstance().apply { setText(rawText) }
        val selection = Path()
        val visibleLine = Path()
        for (word in words) {
            val boxes = ArrayList<Triple<RectF?, Boolean, Double>>()
            var offset = word.offset
            val limit = word.offset + word.length
            while (offset < limit) {
                val next = iterator.following(offset).let { if (it == BreakIterator.DONE) limit else minOf(it, limit) }
                val line = textLayout.getLineForOffset(offset)
                val ellipsisStart = textLayout.getLineStart(line) + textLayout.getEllipsisStart(line)
                val ellipsisEnd = ellipsisStart + textLayout.getEllipsisCount(line)
                if (line < maxLines && rawText.substring(offset, next) != "\n" &&
                    !(offset < ellipsisEnd && next > ellipsisStart)) {
                    selection.rewind()
                    textLayout.getSelectionPath(offset, next, selection)
                    // At a wrap boundary Android also selects the empty tail/head
                    // of adjacent lines. Bounding that whole path makes one final
                    // glyph cover unrelated text. Keep only this physical line.
                    visibleLine.rewind()
                    visibleLine.addRect(textLayout.getLineLeft(line), textLayout.getLineTop(line).toFloat(),
                        textLayout.getLineRight(line), textLayout.getLineBottom(line).toFloat(), Path.Direction.CW)
                    selection.op(visibleLine, Path.Op.INTERSECT)
                    val box = RectF()
                    selection.computeBounds(box, true)
                    if (!box.isEmpty) boxes.add(Triple(box, textLayout.isRtlCharAt(offset), box.width().toDouble()))
                } else if (rawText.substring(offset, next) != "\n") {
                    // Hidden ellipsized text still consumes its part of the
                    // source token's duration; do not accelerate visible letters.
                    val measure = TextPaint(paint)
                    (text as? Spanned)?.getSpans(offset, next, MetricAffectingSpan::class.java)
                        ?.forEach { it.updateMeasureState(measure) }
                    boxes.add(Triple(null, false, measure.measureText(rawText, offset, next).toDouble()))
                }
                offset = next
            }
            val total = boxes.sumOf { it.third }
            if (total <= 0.0) continue
            var travelled = 0.0
            for ((box, rtl, advance) in boxes) {
                val start = word.start + (word.end - word.start) * travelled / total
                travelled += advance
                val end = word.start + (word.end - word.start) * travelled / total
                if (box != null) result.add(Cell(box, start, end, rtl))
            }
        }
        cells = result
        visibleWords = result.map { DesktopLyricWord(0, 1, it.start, it.end) }
        geometryDirty = false
        drawingDirty = true
    }

    override fun onDraw(canvas: Canvas) {
        removeCallbacks(nextFrame)
        val textLayout = layout ?: return
        if (geometryDirty) rebuildCells()
        val save = canvas.save()
        // Padding protects outlines, accents and both edges during fitting.
        canvas.clipRect(0, 0, width, height)
        canvas.translate(compoundPaddingLeft.toFloat(), extendedPaddingTop.toFloat())
        val cached = if (Build.VERSION.SDK_INT >= 29 && canvas.isHardwareAccelerated) {
            val cache = textCache ?: TextCache().also { textCache = it }
            if (drawingDirty || cache.layout !== textLayout) {
                cache.record(textLayout, paint, outlineEnabled, outlineWidth, outlineColor, fillColor, highlightColor)
                drawingDirty = false
            }
            cache
        } else null
        if (cached != null) cached.drawBase(canvas) else {
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
        }
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
            if (cached != null) cached.drawHighlight(canvas) else {
                paint.color = highlightColor
                textLayout.draw(canvas)
            }
            canvas.restore()
            paint.color = fillColor
            if (clock.playing && isAttachedToWindow && isShown && windowVisibility == View.VISIBLE) {
                val delay = desktopLyricFrameDelay(position, visibleWords, clock.rate)
                if (delay == 0L) postOnAnimation(nextFrame)
                else if (delay > 0) postDelayed(nextFrame, delay)
            }
        }
        canvas.restoreToCount(save)
    }

    override fun onDetachedFromWindow() {
        removeCallbacks(nextFrame)
        textCache = null
        super.onDetachedFromWindow()
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        invalidate()
    }

    override fun onWindowVisibilityChanged(visibility: Int) {
        super.onWindowVisibilityChanged(visibility)
        removeCallbacks(nextFrame)
        if (visibility == View.VISIBLE) invalidate()
    }

    @android.annotation.TargetApi(29)
    private class TextCache {
        private val base = android.graphics.RenderNode("desktop-lyric-base")
        private val highlight = android.graphics.RenderNode("desktop-lyric-highlight")
        var layout: android.text.Layout? = null
            private set

        fun record(text: android.text.Layout, paint: TextPaint, stroke: Boolean,
                   width: Float, outline: Int, fill: Int, active: Int) {
            layout = text
            for (node in arrayOf(base, highlight)) {
                node.setPosition(0, 0, text.width, text.height)
                node.setClipToBounds(false)
            }
            val canvas = base.beginRecording()
            if (stroke) {
                paint.style = Paint.Style.STROKE
                paint.strokeWidth = width
                paint.strokeJoin = Paint.Join.ROUND
                paint.color = outline
                text.draw(canvas)
            }
            paint.style = Paint.Style.FILL
            paint.color = fill
            text.draw(canvas)
            base.endRecording()
            paint.color = active
            text.draw(highlight.beginRecording())
            highlight.endRecording()
            paint.color = fill
        }

        fun drawBase(canvas: Canvas) = canvas.drawRenderNode(base)
        fun drawHighlight(canvas: Canvas) = canvas.drawRenderNode(highlight)
    }

}
