package io.github.cidy02.kudos.backup

import android.content.Context
import android.os.Environment
import java.io.File
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.FileAlreadyExistsException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * iOS `PreReplaceBackupNaming` (Settings/SettingsView.swift). Seconds in the name,
 * and a retry in the same second gets its own suffix so it cannot overwrite the
 * copy it is retrying for.
 */
internal object PreReplaceBackupNaming {
    const val attemptLimit = 3
    const val fileExtension = "kudosbackup"

    private val timestamp = DateTimeFormatter.ofPattern("yyyy-MM-dd HH-mm-ss", Locale.US)

    fun fileName(at: Instant, attempt: Int, zone: ZoneId = ZoneId.systemDefault()): String {
        val stamp = timestamp.format(at.atZone(zone))
        val suffix = if (attempt == 0) "" else " (${attempt + 1})"
        return "Kudos Library Before Replace $stamp$suffix.$fileExtension"
    }
}

/**
 * Where Replace writes the undo copy, and the staged move that refuses an
 * existing destination (iOS `makePreReplaceBackup`). The directory is app
 * Documents; [KudosSafetyDocumentsProvider] is what lets Import open it.
 */
internal object SafetyCopies {
    fun directory(context: Context): File {
        val docs = context.getExternalFilesDir(Environment.DIRECTORY_DOCUMENTS)
            ?: File(context.filesDir, "Documents")
        docs.mkdirs()
        return docs
    }

    fun write(directory: File, bytes: ByteArray, at: Instant): String {
        directory.mkdirs()
        var last: Exception? = null
        for (attempt in 0 until PreReplaceBackupNaming.attemptLimit) {
            try {
                return place(directory, bytes, PreReplaceBackupNaming.fileName(at, attempt))
            } catch (error: Exception) {
                last = error
            }
        }
        throw last ?: IOException("Could not save an undo copy.")
    }

    private fun place(directory: File, bytes: ByteArray, name: String): String {
        val root = directory.toPath().normalize()
        val dest = root.resolve(name).normalize()
        require(dest.parent == root) { "Unsafe undo-copy name." }
        if (Files.exists(dest)) throw FileAlreadyExistsException(dest.toString())
        // Dot prefix: a leftover staged file is not a backup the provider lists.
        val staged = Files.createTempFile(root, ".kudos-safety-", ".tmp")
        try {
            Files.write(staged, bytes)
            try {
                Files.move(staged, dest, StandardCopyOption.ATOMIC_MOVE)
            } catch (error: FileAlreadyExistsException) {
                throw error
            } catch (error: IOException) {
                // ATOMIC_MOVE can replace on some systems. Never do that: this file
                // is the only undo a Replace has. A plain move refuses an existing dest.
                if (error is AtomicMoveNotSupportedException || !Files.exists(dest)) {
                    Files.move(staged, dest)
                } else {
                    throw error
                }
            }
            return dest.fileName.toString()
        } finally {
            Files.deleteIfExists(staged)
        }
    }
}
