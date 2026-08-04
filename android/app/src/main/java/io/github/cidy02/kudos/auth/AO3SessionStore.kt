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
    suspend fun delete()
}

/**
 * AES256-GCM encrypted session file under [Context.noBackupFilesDir].
 * Port of iOS Keychain-backed `AO3SessionVault` (file fallback on Simulator).
 *
 * On first load, migrates a legacy plaintext `session.json` if present, then
 * deletes the plaintext copy so credentials/cookies never rest unencrypted.
 */
class EncryptedFileAO3SessionStore(
    context: Context,
    private val json: Json = Json { ignoreUnknownKeys = true }
) : AO3SessionStore {
    private val appContext = context.applicationContext
    private val dir = File(appContext.noBackupFilesDir, "ao3")
    private val encryptedFile = File(dir, "session.enc")
    private val legacyPlainFile = File(dir, "session.json")

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
    }

    override suspend fun delete() = withContext(Dispatchers.IO) {
        deleteBlocking()
    }

    private fun deleteBlocking() {
        if (encryptedFile.exists()) encryptedFile.delete()
        if (legacyPlainFile.exists()) legacyPlainFile.delete()
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
    private val json: Json = Json { ignoreUnknownKeys = true }
) : AO3SessionStore {
    constructor(context: Context) : this(
        sessionFile = File(File(context.noBackupFilesDir, "ao3"), "session.json")
    )

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
    }

    override suspend fun delete() = withContext(Dispatchers.IO) {
        deleteBlocking()
    }

    private fun deleteBlocking() {
        if (sessionFile.exists()) sessionFile.delete()
    }
}
