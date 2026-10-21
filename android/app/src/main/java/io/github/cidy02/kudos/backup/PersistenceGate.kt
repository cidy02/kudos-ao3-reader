package io.github.cidy02.kudos.backup

import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * App-wide persistence operation gate.
 * Migration, backup import, and folder sync all contend for this mutex,
 * so they can never race each other's writes.
 *
 * Re-entrant for the coroutine that already holds it. A Replace and the launch
 * sweep take this lock and then write or delete library files, and those file
 * calls take the same lock. kotlinx's Mutex deadlocks on a second acquire in
 * the same coroutine. The permit rides the coroutine context, including
 * [kotlinx.coroutines.Dispatchers.IO], which is where the bytes move.
 */
open class PersistenceGate {
    private val mutex = Mutex()

    open suspend fun <T> withLock(action: suspend () -> T): T {
        if (currentCoroutineContext()[GatePermit] != null) return action()
        return mutex.withLock {
            withContext(GatePermit()) { action() }
        }
    }
}

private class GatePermit : AbstractCoroutineContextElement(GatePermit) {
    companion object Key : CoroutineContext.Key<GatePermit>
}

/** A folder import refused because Replace paused sync. Not a failure and not a cancellation. */
internal class ImportDeclined : Exception()
