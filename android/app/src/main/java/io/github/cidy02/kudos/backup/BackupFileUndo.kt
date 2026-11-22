package io.github.cidy02.kudos.backup

import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import kotlinx.serialization.json.add
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray

/**
 * Replace's journal: every asset a Replace touches, and the generation that decides its fate.
 * It is one JSON document, rewritten whole through a temp file and an atomic move before each
 * asset is touched, so a process death never leaves a torn or half-written record.
 * [BackupRepository] replays it for success, failure, cancellation and recovery alike.
 */
internal class BackupFileUndo(private val journal: Path, private val generation: String) {
    private val entries = linkedMapOf<Path, Boolean>()

    init {
        writeJournal()
    }

    fun beforeWrite(destination: Path) {
        if (destination in entries) return
        if (Files.exists(asideOf(destination), LinkOption.NOFOLLOW_LINKS)) {
            throw IOException("Unrecovered Replace file: ${asideOf(destination).fileName}")
        }
        val existed = Files.exists(destination, LinkOption.NOFOLLOW_LINKS)
        if (existed && !Files.isRegularFile(destination, LinkOption.NOFOLLOW_LINKS)) {
            throw IOException("Cannot replace a non-file: ${destination.fileName}")
        }
        entries[destination] = existed
        writeJournal()
        // Android disallows hard links; a deterministic sibling survives process death.
        if (existed) Files.move(destination, asideOf(destination), StandardCopyOption.ATOMIC_MOVE)
    }

    private fun writeJournal() {
        val document = buildJsonObject {
            put("generation", generation)
            putJsonArray("entries") {
                entries.forEach { (path, existed) ->
                    add(buildJsonObject { put("path", path.toString()); put("existed", existed) })
                }
            }
        }
        val temp = journal.resolveSibling("${journal.fileName}.tmp")
        java.io.FileOutputStream(temp.toFile()).use {
            it.write(document.toString().toByteArray(Charsets.UTF_8))
            it.fd.sync()
        }
        Files.move(temp, journal, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    }

    companion object {
        const val UNDO_SUFFIX = ".kudos-replace-undo"

        fun asideOf(destination: Path): Path = destination.resolveSibling("${destination.fileName}$UNDO_SUFFIX")

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
