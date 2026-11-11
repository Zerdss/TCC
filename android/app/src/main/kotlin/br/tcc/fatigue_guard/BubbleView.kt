package br.tcc.fatigue_guard

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.MotionEvent
import android.view.View
import kotlin.math.abs

/**
 * Bolinha do indicador flutuante: um ponto colorido (verde/amarelo/vermelho)
 * e o ícone de câmera (riscado com X quando a detecção não está funcionando).
 * Arrastável; um toque abre o app.
 */
@SuppressLint("ViewConstructor")
class BubbleView(context: Context) : View(context) {
    private val d = resources.displayMetrics.density
    private val w = (58 * d).toInt()
    private val h = (30 * d).toInt()

    private var status = 0
    private var cameraOk = false
    private var blinkOn = true

    var onMove: ((Int, Int) -> Unit)? = null
    var onTap: (() -> Unit)? = null

    private val bg = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(60, 0, 0, 0)
        style = Paint.Style.STROKE
        strokeWidth = 1 * d
    }
    private val dot = Paint(Paint.ANTI_ALIAS_FLAG)
    private val icon = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(40, 46, 52) }
    private val cross = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.rgb(179, 38, 30)
        strokeWidth = 2.2f * d
        strokeCap = Paint.Cap.ROUND
    }

    private val blink = object : Runnable {
        override fun run() {
            blinkOn = !blinkOn
            invalidate()
            if (status == 2) postDelayed(this, 400)
        }
    }

    init {
        elevation = 6 * d
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) = setMeasuredDimension(w, h)

    fun update(newStatus: Int, newCameraOk: Boolean) {
        if (newStatus == status && newCameraOk == cameraOk) return
        val wasAlert = status == 2
        status = newStatus
        cameraOk = newCameraOk
        if (!wasAlert || status != 2) {
            removeCallbacks(blink)
            blinkOn = true
            if (status == 2) postDelayed(blink, 400)
        }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        val r = h / 2f
        val box = RectF(0.5f * d, 0.5f * d, w - 0.5f * d, h - 0.5f * d)
        bg.color = if (status == 2 && blinkOn) Color.rgb(255, 228, 225) else Color.WHITE
        canvas.drawRoundRect(box, r, r, bg)
        canvas.drawRoundRect(box, r, r, border)

        // Ponto de status
        dot.color = when (status) {
            2 -> if (blinkOn) Color.rgb(211, 47, 47) else Color.rgb(140, 20, 20)
            1 -> Color.rgb(242, 169, 0)
            else -> Color.rgb(46, 160, 87)
        }
        canvas.drawCircle(r, r, 8 * d, dot)

        // Câmera (corpo + lente triangular)
        val cx = w - r - 2 * d
        val cy = r
        val body = RectF(cx - 9 * d, cy - 5.5f * d, cx + 3 * d, cy + 5.5f * d)
        icon.alpha = if (cameraOk) 255 else 120
        canvas.drawRoundRect(body, 2 * d, 2 * d, icon)
        val lens = Path().apply {
            moveTo(cx + 3.5f * d, cy - 1.5f * d)
            lineTo(cx + 9 * d, cy - 5 * d)
            lineTo(cx + 9 * d, cy + 5 * d)
            lineTo(cx + 3.5f * d, cy + 1.5f * d)
            close()
        }
        canvas.drawPath(lens, icon)
        if (!cameraOk) {
            canvas.drawLine(cx - 9 * d, cy - 8 * d, cx + 9 * d, cy + 8 * d, cross)
            canvas.drawLine(cx + 9 * d, cy - 8 * d, cx - 9 * d, cy + 8 * d, cross)
        }
    }

    private var downX = 0f
    private var downY = 0f
    private var lastX = 0f
    private var lastY = 0f
    private var dragging = false

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = e.rawX; downY = e.rawY; lastX = e.rawX; lastY = e.rawY; dragging = false
            }
            MotionEvent.ACTION_MOVE -> {
                if (abs(e.rawX - downX) > 8 * d || abs(e.rawY - downY) > 8 * d) dragging = true
                if (dragging) {
                    onMove?.invoke((e.rawX - lastX).toInt(), (e.rawY - lastY).toInt())
                    lastX = e.rawX; lastY = e.rawY
                }
            }
            MotionEvent.ACTION_UP -> if (!dragging) onTap?.invoke()
        }
        return true
    }
}
