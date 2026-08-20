package io.github.cidy02.kudos.reader.speech

import android.content.Context
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.Operation
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import java.io.BufferedInputStream
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.apache.commons.compress.archivers.tar.TarArchiveEntry
import org.apache.commons.compress.archivers.tar.TarArchiveInputStream
import org.apache.commons.compress.compressors.bzip2.BZip2CompressorInputStream

class TTSDownloadWorker(
    appContext: Context,
    workerParams: WorkerParameters
) : CoroutineWorker(appContext, workerParams) {

    companion object {
        const val KEY_PROGRESS = "progress"
        const val KEY_PHASE = "phase"
        const val KEY_ERROR = "error"
        const val WORK_NAME = "TTSDownloadWorker"
        const val MODEL_URL = "https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/kokoro-int8-en-v0_19.tar.bz2"

        fun modelDirectory(context: Context): File {
            return File(context.filesDir, "tts_models/kokoro-int8-en-v0_19")
        }

        fun isModelDownloaded(context: Context): Boolean {
            val dir = modelDirectory(context)
            if (!dir.exists() || !dir.isDirectory) return false

            val requiredFiles = listOf("model.int8.onnx", "voices.bin", "tokens.txt")
            for (fileName in requiredFiles) {
                val file = File(dir, fileName)
                if (!file.exists() || file.length() == 0L) return false
            }

            val espeakDir = File(dir, "espeak-ng-data")
            if (!espeakDir.exists() || !espeakDir.isDirectory) return false

            return true
        }

        fun enqueue(context: Context): Operation {
            val request = OneTimeWorkRequestBuilder<TTSDownloadWorker>().build()
            return WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME,
                ExistingWorkPolicy.KEEP,
                request
            )
        }
    }

    override suspend fun doWork(): Result = withContext(Dispatchers.IO) {
        if (isModelDownloaded(applicationContext)) {
            return@withContext Result.success()
        }

        val client = OkHttpClient.Builder()
            .callTimeout(15, TimeUnit.MINUTES)
            .readTimeout(5, TimeUnit.MINUTES)
            .build()

        setProgressAsync(workDataOf(KEY_PHASE to "downloading", KEY_PROGRESS to 0f))

        var tempFile: File? = null
        try {
            tempFile = File.createTempFile("kokoro-model-", ".tar.bz2", applicationContext.cacheDir)

            val request = Request.Builder().url(MODEL_URL).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw IOException("HTTP error ${response.code} downloading TTS model.")
                }

                val body = response.body ?: throw IOException("Empty response body")
                val expectedLength = body.contentLength().takeIf { it > 0 } ?: -1L

                body.byteStream().use { input ->
                    tempFile.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var readTotal = 0L
                        while (true) {
                            val read = input.read(buffer)
                            if (read == -1) break
                            output.write(buffer, 0, read)
                            readTotal += read
                            if (expectedLength > 0) {
                                val progress = (readTotal.toFloat() / expectedLength).coerceIn(0f, 1f)
                                setProgressAsync(workDataOf(KEY_PHASE to "downloading", KEY_PROGRESS to progress))
                            }
                        }
                    }
                }
            }

            setProgressAsync(workDataOf(KEY_PHASE to "extracting", KEY_PROGRESS to 1f))

            val targetDir = modelDirectory(applicationContext)
            targetDir.deleteRecursively()
            targetDir.mkdirs()

            TarArchiveInputStream(BZip2CompressorInputStream(BufferedInputStream(tempFile.inputStream()))).use { tarInput ->
                var entry = tarInput.nextEntry as? TarArchiveEntry
                while (entry != null) {
                    var relativePath = entry.name
                    val prefix = "kokoro-int8-en-v0_19/"
                    if (relativePath.startsWith(prefix)) {
                        relativePath = relativePath.substring(prefix.length)
                    }
                    if (relativePath.isNotEmpty()) {
                        val outFile = File(targetDir, relativePath)
                        if (entry.isDirectory) {
                            outFile.mkdirs()
                        } else {
                            outFile.parentFile?.mkdirs()
                            outFile.outputStream().use { output ->
                                tarInput.copyTo(output)
                            }
                        }
                    }
                    entry = tarInput.nextEntry as? TarArchiveEntry
                }
            }

            if (!isModelDownloaded(applicationContext)) {
                targetDir.deleteRecursively()
                return@withContext Result.failure(workDataOf(KEY_ERROR to "Extraction completed but verification failed."))
            }

            Result.success()
        } catch (e: Exception) {
            modelDirectory(applicationContext).deleteRecursively()
            Result.failure(workDataOf(KEY_ERROR to (e.message ?: "Unknown error")))
        } finally {
            tempFile?.delete()
        }
    }
}
