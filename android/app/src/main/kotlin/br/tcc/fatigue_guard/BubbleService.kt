package br.tcc.fatigue_guard

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.view.Gravity
import android.view.WindowManager
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.LifecycleRegistry
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceContour
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Indicador flutuante: enquanto o motorista usa outro app (ex.: GPS), este
 * serviço mantém a câmera frontal e o ML Kit funcionando e manda os pontos do
 * rosto para o app (a mesma lógica de sonolência do Dart decide o status). Na
 * tela fica só uma bolinha com o ponto colorido e o ícone da câmera.
 */
class BubbleService : Service(), LifecycleOwner {
    private val registry = LifecycleRegistry(this)
    override val lifecycle: Lifecycle get() = registry

    private val main = Handler(Looper.getMainLooper())
    private val executor: ExecutorService = Executors.newSingleThreadExecutor()
    private var provider: ProcessCameraProvider? = null
    private var detector: FaceDetector? = null
    private var bubble: BubbleView? = null
    private var windowManager: WindowManager? = null
    @Volatile private var running = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        registry.currentState = Lifecycle.State.CREATED
        startAsForeground()
        showBubble()
        registry.currentState = Lifecycle.State.STARTED
        running = true
        // Espera o app soltar a câmera antes de abrir.
        main.postDelayed({ startCamera() }, 700)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int = START_NOT_STICKY

    private fun startAsForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Detector em segundo plano", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this, 1, openAppIntent(), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle("Fatigue Guard está monitorando")
            .setContentText("A câmera continua detectando sonolência. Toque para abrir.")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun openAppIntent(): Intent =
        Intent(this, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    // ------------------------------------------------------------------ bolinha
    private fun showBubble() {
        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        windowManager = wm
        val view = BubbleView(this)
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.TRANSLUCENT,
        )
        params.gravity = Gravity.TOP or Gravity.START
        val d = resources.displayMetrics.density
        params.x = (12 * d).toInt()
        params.y = (110 * d).toInt()
        view.onMove = { dx, dy ->
            params.x += dx
            params.y += dy
            try {
                wm.updateViewLayout(view, params)
            } catch (_: Exception) {
            }
        }
        view.onTap = { startActivity(openAppIntent()) }
        try {
            wm.addView(view, params)
            bubble = view
        } catch (_: Exception) {
            bubble = null
        }
    }

    /** Atualiza a bolinha: 0 = normal (verde), 1 = atenção (amarelo), 2 = alerta (vermelho). */
    fun setStatus(status: Int, cameraOk: Boolean) {
        main.post { bubble?.update(status, cameraOk) }
    }

    // ------------------------------------------------------------------ câmera
    private fun startCamera() {
        if (!running) return
        detector = FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setContourMode(FaceDetectorOptions.CONTOUR_MODE_ALL)
                .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
                .setMinFaceSize(0.15f)
                .build(),
        )
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            if (!running) return@addListener
            try {
                val p = future.get()
                provider = p
                val analysis = ImageAnalysis.Builder()
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .build()
                analysis.setAnalyzer(executor) { proxy -> analyze(proxy) }
                p.unbindAll()
                p.bindToLifecycle(this, CameraSelector.DEFAULT_FRONT_CAMERA, analysis)
            } catch (e: Exception) {
                // Câmera ainda ocupada: tenta de novo em 1 s.
                main.postDelayed({ startCamera() }, 1000)
            }
        }, { main.post(it) })
    }

    @androidx.annotation.OptIn(ExperimentalGetImage::class)
    private fun analyze(proxy: ImageProxy) {
        val media = proxy.image
        val det = detector
        if (media == null || det == null || !running) {
            proxy.close()
            return
        }
        val lum = meanLuma(proxy)
        val rotation = proxy.imageInfo.rotationDegrees
        val upright = rotation % 180 == 0
        val w = if (upright) proxy.width else proxy.height
        val h = if (upright) proxy.height else proxy.width
        det.process(InputImage.fromMediaImage(media, rotation))
            .addOnSuccessListener(executor) { faces ->
                val frame = toMap(faces, w, h)
                frame["lum"] = lum
                main.post { if (running) sink?.invoke(frame) }
            }
            .addOnCompleteListener { proxy.close() }
    }

    /** Brilho médio (0 a 255) do plano Y, lendo só alguns pontos (modo noite). */
    private fun meanLuma(proxy: ImageProxy): Double {
        return try {
            val buf = proxy.planes[0].buffer
            val lim = buf.remaining()
            var sum = 0L
            var n = 0
            var i = 0
            while (i < lim) {
                sum += (buf.get(i).toInt() and 0xFF)
                n++
                i += 97
            }
            if (n == 0) 0.0 else sum.toDouble() / n
        } catch (_: Exception) {
            0.0
        }
    }

    private fun toMap(faces: List<Face>, w: Int, h: Int): HashMap<String, Any?> {
        val m = HashMap<String, Any?>()
        m["w"] = w.toDouble()
        m["h"] = h.toDouble()
        val face = faces.maxByOrNull { it.boundingBox.width() * it.boundingBox.height() } ?: return m
        val b = face.boundingBox
        m["box"] = doubleArrayOf(b.left.toDouble(), b.top.toDouble(), b.right.toDouble(), b.bottom.toDouble())
        fun pts(type: Int): DoubleArray? {
            val ps = face.getContour(type)?.points ?: return null
            val a = DoubleArray(ps.size * 2)
            ps.forEachIndexed { i, p ->
                a[2 * i] = p.x.toDouble()
                a[2 * i + 1] = p.y.toDouble()
            }
            return a
        }
        m["le"] = pts(FaceContour.LEFT_EYE)
        m["re"] = pts(FaceContour.RIGHT_EYE)
        m["ult"] = pts(FaceContour.UPPER_LIP_TOP)
        m["ulb"] = pts(FaceContour.UPPER_LIP_BOTTOM)
        m["llt"] = pts(FaceContour.LOWER_LIP_TOP)
        m["llb"] = pts(FaceContour.LOWER_LIP_BOTTOM)
        m["ex"] = face.headEulerAngleX.toDouble()
        m["ey"] = face.headEulerAngleY.toDouble()
        m["ez"] = face.headEulerAngleZ.toDouble()
        m["lp"] = face.leftEyeOpenProbability?.toDouble()
        m["rp"] = face.rightEyeOpenProbability?.toDouble()
        m["sp"] = face.smilingProbability?.toDouble()
        return m
    }

    /** Solta a câmera na hora (o app vai voltar a usá-la). */
    fun shutdown() {
        running = false
        try {
            provider?.unbindAll()
        } catch (_: Exception) {
        }
        provider = null
        stopSelf()
    }

    override fun onDestroy() {
        running = false
        registry.currentState = Lifecycle.State.DESTROYED
        try {
            provider?.unbindAll()
        } catch (_: Exception) {
        }
        detector?.close()
        bubble?.let {
            try {
                windowManager?.removeView(it)
            } catch (_: Exception) {
            }
        }
        bubble = null
        executor.shutdown()
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "fatigue_guard_background"
        private const val NOTIFICATION_ID = 42

        @Volatile var instance: BubbleService? = null

        /** Recebe cada quadro (no thread principal) e repassa ao Dart. */
        var sink: ((Map<String, Any?>) -> Unit)? = null

        fun start(context: Context) {
            val intent = Intent(context, BubbleService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }
    }
}
