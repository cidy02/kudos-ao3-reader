package io.github.cidy02.kudos.backup

import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.StandardCopyOption

/** Replace-only undo for atomic replacements and newly created assets. Never serialized. */
internal class BackupFileUndo {
    private val previous = linkedMapOf<Path, Path?>()

    fun beforeWrite(destination: Path) {
        if (destination in previous) return
        val undo = destination.resolveSibling("${destination.fileName}$UNDO_SUFFIX")
        if (Files.exists(undo, LinkOption.NOFOLLOW_LINKS)) {
            throw IOException("Unrecovered Replace file: ${undo.fileName}")
        }
        if (!Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
            previous[destination] = null
            return
        }
        if (!Files.isRegularFile(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw IOException("Cannot replace a non-file: ${destination.fileName}")
        }
        // Android disallows hard links; a deterministic sibling survives process death.
        Files.move(destination, undo, StandardCopyOption.ATOMIC_MOVE)
        previous[destination] = undo
    }

    fun rollback(error: Throwable) {
        // Synchronous I/O also runs when the import coroutine was cancelled. Attempt every
        // undo; retain the aside if an exceptional filesystem error blocks undo.
        previous.entries.toList().asReversed().forEach { (destination, undo) ->
            try {
                Files.deleteIfExists(destination)
                if (undo != null) Files.move(undo, destination, StandardCopyOption.ATOMIC_MOVE)
                previous.remove(destination)
            } catch (failure: Throwable) {
                error.addSuppressed(failure)
            }
        }
    }

    fun discard() {
        // Once Room commits, cleanup cannot turn a successful Replace into an error.
        previous.values.filterNotNull().forEach { runCatching { Files.deleteIfExists(it) } }
    }

    companion object {
        const val UNDO_SUFFIX = ".kudos-replace-undo"

        /** Caller holds the persistence gate; never sweep an active Replace's asides. */
        fun recover(vararg directories: Path) {
            directories.forEach { directory ->
                if (!Files.isDirectory(directory)) return@forEach
                Files.newDirectoryStream(directory, "*$UNDO_SUFFIX").use { stream ->
                    stream.forEach { undo ->
                        val name = undo.fileName.toString().removeSuffix(UNDO_SUFFIX)
                        if (name.isNotEmpty() && Files.isRegularFile(undo, LinkOption.NOFOLLOW_LINKS)) {
                            val destination = undo.resolveSibling(name)
                            if (Files.exists(destination, LinkOption.NOFOLLOW_LINKS)) {
                                Files.delete(undo)
                            } else {
                                Files.move(undo, destination, StandardCopyOption.ATOMIC_MOVE)
                            }
                        }
                    }
                }
            }
        }
    }
}
