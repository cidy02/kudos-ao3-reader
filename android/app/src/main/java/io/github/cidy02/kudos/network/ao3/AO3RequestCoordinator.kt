package io.github.cidy02.kudos.network.ao3

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit

class AO3RequestCoordinator(
    private val config: AO3NetworkConfig = AO3NetworkConfig(),
    private val clock: AO3Clock = SystemAO3Clock,
    private val delay: AO3Delay = CoroutineAO3Delay
) {
    private val semaphore = Semaphore(config.maxConcurrentRequests)
    private val spacingMutex = Mutex()
    private var hasStartedRequest = false
    private var nextRequestStartMillis = 0L

    suspend fun <T> coordinate(operation: suspend () -> T): T {
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
            hasStartedRequest = true
            nextRequestStartMillis = clock.nowMillis() + config.minDelayBetweenRequestsMillis
        }
    }
}
