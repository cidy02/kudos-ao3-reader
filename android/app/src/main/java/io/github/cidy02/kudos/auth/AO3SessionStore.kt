package io.github.cidy02.kudos.auth

import android.content.Context
import androidx.security.crypto.EncryptedFile
import androidx.security.crypto.MasterKey
import java.io.File
import java.nio.charset.StandardCharsets
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

interface AO3SessionStore {
    suspend fun load(): AO3Session?
    suspend fun save(session: AO3Session)
    /**
     * Removes any durable session file.
     *
     * @return `true` when no reusable session file remains (or never existed);
     *   `false` when a delete failed and credentials may still be on disk.
     */
    suspend fun delete(): Boolean

    /** A previous logout/expiry could not fully erase the durable session. */
    suspend fun isRemovalPending(): Boolean

    /** Mark that restore must refuse until [delete] succeeds. */
    suspend fun markRemovalPending()

    /** Clear the removal-pending flag after a successful delete or intentional save. */
    suspend fun clearRemovalPending()
}

/**
 * AES256-GCM encrypted session file under [Context.noBackupFilesDir].
 * Port of iOS Keychain-backed `AO3SessionVault` (file fallback on Simulator).
 *
 * On first load, migrates a legacy plaintext `session.json` if present, then
 * deletes the plaintext copy so credentials/cookies never rest unencrypted.
 *
 * Removal-pending is a non-secret sibling marker file (port of iOS
 * `UserDefaultsAO3SessionRemovalTracker`): while set, [AO3AuthRepository.restoreSession]
 * must refuse to load any leftover session blob.
 */
class EncryptedFileAO3SessionStore(
    context: Context,
    private val json: Json = Json {
        ignoreUnknownKeys = true
        // Persist every field, including ones equal to their default.
        // `savedAtEpochMillis` defaults to `Clock.systemUTC().millis()`, and
        // kotlinx.serialization re-evaluates that default when deciding whether
        // to omit it — so a session constructed and written inside the same
        // millisecond had the field silently dropped from the file, and a later
        // load re-stamped it with load time instead. Harmless while nothing
        // reads it; a trap the moment anything treats it as a session age.
        encodeDefaults = true
    }
) : AO3SessionStore {
    private val appContext = context.applicationContext
    private val dir = File(appContext.noBackupFilesDir, "ao3")
    private val encryptedFile = File(dir, "session.enc")
    private val legacyPlainFile = File(dir, "session.json")
    private val removalPendingFile = File(dir, "session.removal_pending")

    private val masterKey: MasterKey by lazy {
        MasterKey.Builder(appContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
    }

    override suspend fun load(): AO3Session? = withContext(Dispatchers.IO) {
        migrateLegacyPlaintextIfNeeded()
        if (!encryptedFile.exists()) return@withContext null
        try {
            val bytes = openEncrypted(forWrite = false).openFileInput().use { it.readBytes() }
            json.decodeFromString(AO3Session.serializer(), bytes.toString(StandardCharsets.UTF_8))
        } catch (_: IllegalArgumentException) {
            deleteBlocking()
            null
        } catch (_: SerializationException) {
            deleteBlocking()
            null
        } catch (_: Exception) {
            // Corrupt keyset / IO — treat as signed-out rather than crash launch.
            null
        }
    }

    override suspend fun save(session: AO3Session) = withContext(Dispatchers.IO) {
        dir.mkdirs()
        if (encryptedFile.exists()) encryptedFile.delete()
        val payload = json.encodeToString(AO3Session.serializer(), session)
            .toByteArray(StandardCharsets.UTF_8)
        openEncrypted(forWrite = true).openFileOutput().use { out ->
            out.write(payload)
        }
        // Never leave a plaintext twin behind.
        if (legacyPlainFile.exists()) legacyPlainFile.delete()
        // A fresh intentional save supersedes any earlier failed-logout marker.
        clearRemovalPendingBlocking()
    }

    override suspend fun delete(): Boolean = withContext(Dispatchers.IO) {
        deleteBlocking()
    }

    override suspend fun isRemovalPending(): Boolean = withContext(Dispatchers.IO) {
        removalPendingFile.exists()
    }

    override suspend fun markRemovalPending() = withContext(Dispatchers.IO) {
        dir.mkdirs()
        if (!removalPendingFile.exists()) {
            removalPendingFile.writeText("1")
        }
    }

    override suspend fun clearRemovalPending() = withContext(Dispatchers.IO) {
        clearRemovalPendingBlocking()
    }

    private fun clearRemovalPendingBlocking() {
        if (removalPendingFile.exists()) removalPendingFile.delete()
    }

    /**
     * @return true if no session file remains (or never existed).
     */
    private fun deleteBlocking(): Boolean {
        var fullyGone = true
        if (encryptedFile.exists() && !encryptedFile.delete()) {
            fullyGone = false
        }
        if (legacyPlainFile.exists() && !legacyPlainFile.delete()) {
            fullyGone = false
        }
        return fullyGone
    }

    private fun openEncrypted(forWrite: Boolean): EncryptedFile {
        return EncryptedFile.Builder(
            appContext,
            encryptedFile,
            masterKey,
            EncryptedFile.FileEncryptionScheme.AES256_GCM_HKDF_4KB
        ).build()
    }

    private fun migrateLegacyPlaintextIfNeeded() {
        if (!legacyPlainFile.exists() || encryptedFile.exists()) return
        try {
            val text = legacyPlainFile.readText(StandardCharsets.UTF_8)
            val session = json.decodeFromString(AO3Session.serializer(), text)
            // Inline save without dispatchers (already on IO).
            dir.mkdirs()
            if (encryptedFile.exists()) encryptedFile.delete()
            val payload = json.encodeToString(AO3Session.serializer(), session)
                .toByteArray(StandardCharsets.UTF_8)
            openEncrypted(forWrite = true).openFileOutput().use { it.write(payload) }
            legacyPlainFile.delete()
        } catch (_: Exception) {
            // Leave legacy file; next successful login will overwrite.
        }
    }
}

/**
 * Legacy plaintext store retained only for unit tests that don't need Android Keystore.
 * Production uses [EncryptedFileAO3SessionStore].
 */
class FileAO3SessionStore(
    private val sessionFile: File,
    private val json: Json = Json {
        ignoreUnknownKeys = true
        // Persist every field, including ones equal to their default.
        // `savedAtEpochMillis` defaults to `Clock.systemUTC().millis()`, and
        // kotlinx.serialization re-evaluates that default when deciding whether
        // to omit it — so a session constructed and written inside the same
        // millisecond had the field silently dropped from the file, and a later
        // load re-stamped it with load time instead. Harmless while nothing
        // reads it; a trap the moment anything treats it as a session age.
        encodeDefaults = true
    }
) : AO3SessionStore {
    constructor(context: Context) : this(
        sessionFile = File(File(context.noBackupFilesDir, "ao3"), "session.json")
    )

    private val removalPendingFile: File =
        File(sessionFile.parentFile ?: File("."), "${sessionFile.name}.removal_pending")

    override suspend fun load(): AO3Session? = withContext(Dispatchers.IO) {
        if (!sessionFile.exists()) return@withContext null
        try {
            json.decodeFromString(AO3Session.serializer(), sessionFile.readText())
        } catch (error: IllegalArgumentException) {
            deleteBlocking()
            null
        } catch (error: SerializationException) {
            deleteBlocking()
            null
        }
    }

    override suspend fun save(session: AO3Session) = withContext(Dispatchers.IO) {
        sessionFile.parentFile?.mkdirs()
        val temp = File(sessionFile.parentFile, "${sessionFile.name}.tmp")
        temp.writeText(json.encodeToString(AO3Session.serializer(), session))
        if (!temp.renameTo(sessionFile)) {
            temp.copyTo(sessionFile, overwrite = true)
            temp.delete()
        }
        clearRemovalPendingBlocking()
    }

    override suspend fun delete(): Boolean = withContext(Dispatchers.IO) {
        deleteBlocking()
    }

    override suspend fun isRemovalPending(): Boolean = withContext(Dispatchers.IO) {
        removalPendingFile.exists()
    }

    override suspend fun markRemovalPending() = withContext(Dispatchers.IO) {
        sessionFile.parentFile?.mkdirs()
        if (!removalPendingFile.exists()) {
            removalPendingFile.writeText("1")
        }
    }

    override suspend fun clearRemovalPending() = withContext(Dispatchers.IO) {
        clearRemovalPendingBlocking()
    }

    private fun clearRemovalPendingBlocking() {
        if (removalPendingFile.exists()) removalPendingFile.delete()
    }

    private fun deleteBlocking(): Boolean {
        if (!sessionFile.exists()) return true
        return sessionFile.delete()
    }
}
