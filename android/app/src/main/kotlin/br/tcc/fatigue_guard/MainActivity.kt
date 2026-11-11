package br.tcc.fatigue_guard

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Janela flutuante (picture-in-picture): o app continua detectando numa janela
 * pequena por cima de outro app (ex.: GPS). A câmera e o ML Kit seguem ativos
 * porque a janela continua visível.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var autoEnter = false
    private var receiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).also { ch ->
            ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isSupported" -> result.success(pipSupported())
                    "isInPip" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInPictureInPictureMode)
                    "enter" -> result.success(enterPip())
                    "setAuto" -> {
                        autoEnter = call.argument<Boolean>("enabled") == true
                        updateParams()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        registerAckReceiver()
    }

    private fun pipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun params(): PictureInPictureParams? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return null
        val ack = PendingIntent.getBroadcast(
            this, 0, Intent(ACTION_ACK).setPackage(packageName),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val action = RemoteAction(
            Icon.createWithResource(this, android.R.drawable.ic_lock_silent_mode),
            "Estou acordado", "Silencia o alerta por 10 s", ack,
        )
        val b = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(3, 2))
            .setActions(listOf(action))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            b.setAutoEnterEnabled(autoEnter)
            b.setSeamlessResizeEnabled(false)
        }
        return b.build()
    }

    private fun updateParams() {
        if (!pipSupported()) return
        try {
            params()?.let { setPictureInPictureParams(it) }
        } catch (_: Exception) {
        }
    }

    private fun enterPip(): Boolean {
        if (!pipSupported()) return false
        return try {
            params()?.let { enterPictureInPictureMode(it) } ?: false
        } catch (_: Exception) {
            false
        }
    }

    /** Android 8 a 11: entra na janela flutuante ao apertar "início" durante o monitoramento. */
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnter && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pipChanged", isInPictureInPictureMode)
    }

    /** Botão "Estou acordado" da janela flutuante. */
    private fun registerAckReceiver() {
        if (receiver != null || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val r = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                channel?.invokeMethod("ack", null)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(r, IntentFilter(ACTION_ACK), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(r, IntentFilter(ACTION_ACK))
        }
        receiver = r
    }

    override fun onDestroy() {
        receiver?.let { unregisterReceiver(it) }
        receiver = null
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "fatigue_guard/pip"
        private const val ACTION_ACK = "br.tcc.fatigue_guard.ACK_ALERT"
    }
}
