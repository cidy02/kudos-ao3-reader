package io.github.cidy02.kudos.backup

import java.time.Instant
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Android's Room schema is migrated on open; check the local sync manifest without exporting assets. */
class SyncMetadataCheck(private val now: () -> Instant = { Instant.now() }, private val check: suspend () -> Unit) {
    data class Status(
        val checking: Boolean = false,
        val lastChecked: Instant? = null,
        val error: String? = null
    ) {
        val title: String get() = when {
            checking -> "Preparing"
            error != null -> "Needs Retry"
            lastChecked != null -> "Ready"
            else -> "Not Started"
        }
        val action: String get() = if (error != null || lastChecked == null) "Retry Metadata Prep" else "Check Metadata"
    }

    private val mutableStatus = MutableStateFlow(Status())
    val status = mutableStatus.asStateFlow()

    suspend fun run() {
        val previous = mutableStatus.value
        if (previous.checking || !mutableStatus.compareAndSet(previous, previous.copy(checking = true))) return
        try {
            check()
            mutableStatus.value = Status(lastChecked = now())
        } catch (cancelled: CancellationException) {
            mutableStatus.value = previous
            throw cancelled
        } catch (error: Exception) {
            mutableStatus.value = Status(lastChecked = now(), error = error.message ?: "Couldn't check your library metadata.")
        }
    }
}
