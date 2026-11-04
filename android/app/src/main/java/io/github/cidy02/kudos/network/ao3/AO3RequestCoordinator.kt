package io.github.cidy02.kudos.network.ao3

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit

class AO3MaintenanceException : RuntimeException("AO3 is down for maintenance.")

class AO3RequestCoordinator(
    private val config: AO3NetworkConfig = AO3NetworkConfig(),
    private val clock: AO3Clock = SystemAO3Clock,
    private val delay: AO3Delay = CoroutineAO3Delay
) {
    private val semaphore = Semaphore(config.maxConcurrentRequests)
    private val spacingMutex = Mutex()
    private var hasStartedRequest = false
    private var nextRequestStartMillis = 0L

    companion object {
        const val MAINTENANCE_HOLD_MILLIS: Long = 60_000L
    }

    @Volatile
    private var maintenanceHoldUntilMillis: Long = 0L

    fun holdForMaintenance(durationMillis: Long = MAINTENANCE_HOLD_MILLIS) {
        maintenanceHoldUntilMillis = clock.nowMillis() + durationMillis
    }

    fun liftMaintenanceHold() {
        maintenanceHoldUntilMillis = 0L
    }

    fun isHeldForMaintenance(): Boolean {
        return clock.nowMillis() < maintenanceHoldUntilMillis
    }

    private fun throwIfHeldForMaintenance() {
        if (isHeldForMaintenance()) {
            throw AO3MaintenanceException()
        }
    }

    suspend fun <T> coordinate(operation: suspend () -> T): T {
        // Before the slot claim: a held request books no pacer time or concurrency slot.
        throwIfHeldForMaintenance()
        return semaphore.withPermit {
            awaitSpacingTurn()
            operation()
        }
    }

    private suspend fun awaitSpacingTurn() {
        spacingMutex.withLock {
            val now = clock.nowMillis()
            if (hasStartedRequest) {
                val waitMillis = (nextRequestStartMillis - now).coerceAtLeast(0)
                if (waitMillis > 0) delay.delay(waitMillis)
            }
            // A request that waited here must not go out after another one met the maintenance page meanwhile.
            throwIfHeldForMaintenance()
            hasStartedRequest = true
            nextRequestStartMillis = clock.nowMillis() + config.minDelayBetweenRequestsMillis
        }
    }
}
