package io.github.cidy02.kudos.support

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext
import kotlin.math.sqrt

/**
 * Pure shake threshold / debounce math (no SensorManager dependency so unit tests
 * stay on the plain JVM).
 *
 * Android has no OS-level shake gesture (unlike iOS UIWindow.motionEnded), so we
 * approximate one: each accelerometer sample's vector magnitude minus gravity.
 *
 * Threshold **13.5 m/s²** sits mid-band of the commonly cited 12–15 range —
 * high enough to ignore walking/typing jostles, low enough for a deliberate
 * phone shake. Debounce **1500 ms** so one physical shake does not open multiple
 * mail intents or spam during a sustained rattle.
 */
object ShakeMath {
    /** Combined acceleration delta above gravity that counts as a shake. */
    const val THRESHOLD_MS2 = 13.5f

    /** Minimum gap between successive shake actions. */
    const val DEBOUNCE_MS = 1_500L

    /** Standard gravity; matches [SensorManager.GRAVITY_EARTH]. */
    const val GRAVITY_MS2 = 9.80665f

    /** Acceleration magnitude minus gravity (m/s²). Positive when net force > g. */
    fun accelerationDelta(x: Float, y: Float, z: Float): Float {
        val magnitude = sqrt(x * x + y * y + z * z)
        return magnitude - GRAVITY_MS2
    }

    fun isShake(delta: Float, threshold: Float = THRESHOLD_MS2): Boolean =
        delta > threshold

    fun shouldFire(
        nowMs: Long,
        lastFireMs: Long,
        debounceMs: Long = DEBOUNCE_MS
    ): Boolean = nowMs - lastFireMs >= debounceMs
}

/**
 * Lifecycle-aware accelerometer listener that invokes [onShake] when a physical
 * shake is detected. Registers only while this composition is active and is a
 * no-op when the device has no accelerometer.
 *
 * Wire near app root (e.g. [io.github.cidy02.kudos.app.KudosApp]) so shake works
 * from any screen without a global event bus.
 */
@Composable
fun ShakeToReportEffect(onShake: () -> Unit) {
    val context = LocalContext.current
    val latestOnShake by rememberUpdatedState(onShake)

    DisposableEffect(context.applicationContext) {
        val sensorManager = context.applicationContext
            .getSystemService(Context.SENSOR_SERVICE) as SensorManager
        val accelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
        if (accelerometer == null) {
            return@DisposableEffect onDispose { }
        }

        var lastFireMs = 0L
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
                val values = event.values
                if (values.size < 3) return
                val delta = ShakeMath.accelerationDelta(values[0], values[1], values[2])
                if (!ShakeMath.isShake(delta)) return
                val now = System.currentTimeMillis()
                if (!ShakeMath.shouldFire(now, lastFireMs)) return
                lastFireMs = now
                latestOnShake()
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        sensorManager.registerListener(
            listener,
            accelerometer,
            SensorManager.SENSOR_DELAY_UI
        )
        onDispose {
            sensorManager.unregisterListener(listener)
        }
    }
}
