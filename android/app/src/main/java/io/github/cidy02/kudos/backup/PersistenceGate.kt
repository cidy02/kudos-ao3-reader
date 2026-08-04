package io.github.cidy02.kudos.backup

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * App-wide persistence operation gate.
 * Migration, backup import, and folder sync all contend for this mutex,
 * so they can never race each other's writes.
 */
class PersistenceGate {
    private val mutex = Mutex()

    suspend fun <T> withLock(action: suspend () -> T): T {
        return mutex.withLock {
            action()
        }
    }
}
