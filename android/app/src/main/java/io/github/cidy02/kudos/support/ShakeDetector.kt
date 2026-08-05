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

    /** Below this, a sample is noise floor, not a real swing — ignored for reversals. */
    const val REVERSAL_MAGNITUDE_FLOOR_MS2 = 2f

    /** How far back a reversal still counts toward the current gesture. */
    const val REVERSAL_WINDOW_MS = 600L

    /**
     * A single hard jolt (a bump, being picked up or set down) has one spike and no
     * back-and-forth; a deliberate shake oscillates. Requiring this many direction
     * reversals on top of [THRESHOLD_MS2] is the standard technique real shake
     * detectors use to reject that kind of accidental trigger — unlike iOS, which
     * gets a version of this for free from `UIWindow.motionShake`'s own built-in
     * heuristic, Android has no OS-level shake gesture to inherit it from.
     */
    const val REQUIRED_REVERSALS = 2

    /**
     * True when two consecutive linear-acceleration samples (gravity already
     * removed, unlike the raw accelerometer [accelerationDelta] reads) point in
     * substantially opposite directions (dot product < 0) and both clear the noise
     * floor — the back-and-forth pattern of a real shake, as opposed to a single
     * sustained jolt that a bare magnitude threshold can't tell apart from one.
     */
    fun samplesReversed(
        x1: Float,
        y1: Float,
        z1: Float,
        x2: Float,
        y2: Float,
        z2: Float,
        magnitudeFloor: Float = REVERSAL_MAGNITUDE_FLOOR_MS2
    ): Boolean {
        val mag1 = sqrt(x1 * x1 + y1 * y1 + z1 * z1)
        val mag2 = sqrt(x2 * x2 + y2 * y2 + z2 * z2)
        if (mag1 < magnitudeFloor || mag2 < magnitudeFloor) return false
        return (x1 * x2 + y1 * y2 + z1 * z2) < 0
    }
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
        // Gravity-free vector, used only to count direction reversals (see
        // ShakeMath.samplesReversed) — the raw accelerometer above stays the
        // magnitude-threshold source, unchanged, so its already-tuned 13.5 m/s²
        // constant needs no re-tuning. Virtually universal on real devices, but a
        // fused/software sensor some very old hardware lacks — when absent, this
        // falls back to the old threshold-only behavior rather than blocking shake
        // entirely.
        val linearAccelerometer = sensorManager.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)

        val vibrator = ShakeHaptics.from(context.applicationContext)
        var lastFireMs = 0L
        var lastLinearSample: FloatArray? = null
        val reversalTimestamps = ArrayDeque<Long>()

        fun recentReversals(now: Long): Int {
            while (reversalTimestamps.isNotEmpty() && now - reversalTimestamps.first() > ShakeMath.REVERSAL_WINDOW_MS) {
                reversalTimestamps.removeFirst()
            }
            return reversalTimestamps.size
        }

        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                val values = event.values
                if (values.size < 3) return

                if (event.sensor.type == Sensor.TYPE_LINEAR_ACCELERATION) {
                    val now = System.currentTimeMillis()
                    lastLinearSample?.let { last ->
                        if (ShakeMath.samplesReversed(
                                values[0], values[1], values[2],
                                last[0], last[1], last[2]
                            )
                        ) {
                            reversalTimestamps.addLast(now)
                            recentReversals(now)
                        }
                    }
                    lastLinearSample = values.copyOf(3)
                    return
                }

                if (event.sensor.type != Sensor.TYPE_ACCELEROMETER) return
                val delta = ShakeMath.accelerationDelta(values[0], values[1], values[2])
                if (!ShakeMath.isShake(delta)) return
                val now = System.currentTimeMillis()
                if (!ShakeMath.shouldFire(now, lastFireMs)) return
                if (linearAccelerometer != null && recentReversals(now) < ShakeMath.REQUIRED_REVERSALS) return
                lastFireMs = now
                // Confirm the gesture was accepted before the report UI appears
                // (iOS fires a success notification haptic at the same point).
                vibrator?.confirm()
                latestOnShake()
            }

            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }

        sensorManager.registerListener(
            listener,
            accelerometer,
            SensorManager.SENSOR_DELAY_UI
        )
        if (linearAccelerometer != null) {
            sensorManager.registerListener(
                listener,
                linearAccelerometer,
                SensorManager.SENSOR_DELAY_UI
            )
        }
        onDispose {
            sensorManager.unregisterListener(listener)
        }
    }
}

/**
 * Short confirmation buzz when a shake is accepted. Silently absent on devices
 * without a vibrator — feedback is a nicety, never a requirement for reporting.
 */
private object ShakeHaptics {
    fun from(context: Context): Buzzer? {
        val vibrator = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
            val manager = context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE)
                as? android.os.VibratorManager
            manager?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            context.getSystemService(Context.VIBRATOR_SERVICE) as? android.os.Vibrator
        }
        return vibrator?.takeIf { it.hasVibrator() }?.let { Buzzer(it) }
    }

    class Buzzer(private val vibrator: android.os.Vibrator) {
        fun confirm() {
            runCatching {
                vibrator.vibrate(
                    android.os.VibrationEffect.createOneShot(
                        40L,
                        android.os.VibrationEffect.DEFAULT_AMPLITUDE
                    )
                )
            }
        }
    }
}
