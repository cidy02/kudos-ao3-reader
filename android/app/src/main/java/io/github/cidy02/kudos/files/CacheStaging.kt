package io.github.cidy02.kudos.files

import java.io.File
import java.nio.file.Files
import java.nio.file.Path
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.ThreadContextElement

/**
 * Creates a temp file and remembers it for the caller that asked to watch.
 * EPUB package checks and font validation delete the file before they return,
 * including when they fail, so a test cannot see it afterwards unless creation
 * itself records the path. The record is a thread local: import runs on
 * [kotlinx.coroutines.Dispatchers.IO], and [Probe] copies the list onto that thread.
 */
internal object CacheStaging {
    private val seen = ThreadLocal<MutableList<File>?>()

    fun <T> captureInto(into: MutableList<File>, block: () -> T): T {
        val previous = seen.get()
        seen.set(into)
        try {
            return block()
        } finally {
            seen.set(previous)
        }
    }

    class Probe(private val into: MutableList<File>) : ThreadContextElement<MutableList<File>?> {
        companion object Key : CoroutineContext.Key<Probe>

        override val key: CoroutineContext.Key<*>
            get() = Key

        override fun updateThreadContext(context: CoroutineContext): MutableList<File>? {
            val previous = seen.get()
            seen.set(into)
            return previous
        }

        override fun restoreThreadContext(context: CoroutineContext, oldState: MutableList<File>?) {
            seen.set(oldState)
        }
    }

    fun file(directory: File, prefix: String, suffix: String): File {
        val created = File.createTempFile(prefix, suffix, directory)
        seen.get()?.add(created)
        return created
    }

    fun path(directory: Path, prefix: String, suffix: String): Path {
        val created = Files.createTempFile(directory, prefix, suffix)
        seen.get()?.add(created.toFile())
        return created
    }
}
