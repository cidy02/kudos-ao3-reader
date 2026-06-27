package io.github.cidy02.kudos.auth

import android.content.Context
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

interface AO3SessionStore {
    suspend fun load(): AO3Session?
    suspend fun save(session: AO3Session)
    suspend fun delete()
}

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
