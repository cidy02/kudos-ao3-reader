package io.github.cidy02.kudos.update

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import io.github.cidy02.kudos.network.github.GitHubReleaseAsset
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request

/** ZIP local-file-header magic — an APK is a ZIP; a truncated/corrupt download won't have it. */
private val ZIP_MAGIC = byteArrayOf(0x50, 0x4B, 0x03, 0x04)

/**
 * Downloads a release APK asset and hands it to the system installer.
 *
 * A regular (non-system, non-device-owner) app cannot install another APK
 * without the user confirming the system's own install prompt — there is no
 * fully silent path here. This gets the app as close to "self-updating" as a
 * sideloaded app can honestly get: download happens automatically in the
 * background, and the one unavoidable step is a single tap on the system's
 * own "Install" button.
 */
class AppUpdateInstaller(
    private val appContext: Context,
    private val fileProviderAuthority: String = "${appContext.packageName}.fileprovider"
) {
    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .callTimeout(5, TimeUnit.MINUTES)
            .build()
    }

    private val updatesDirectory: Path
        get() = appContext.filesDir.toPath().resolve("updates")

    /**
     * Streams [asset] to app-private storage via a temp-file-then-atomic-move
     * (mirrors [io.github.cidy02.kudos.files.FontFileStore]), validating the
     * downloaded size against what GitHub reported and that it's really a ZIP
     * (an APK). Reports progress in `0f..1f` via [onProgress]; GitHub may omit
     * `Content-Length` on rare CDN paths, in which case progress just won't
     * advance until completion.
     */
    suspend fun download(
        asset: GitHubReleaseAsset,
        onProgress: (Float) -> Unit = {}
    ): Path = withContext(Dispatchers.IO) {
        Files.createDirectories(updatesDirectory)
        val destination = updatesDirectory.resolve(safeFileName(asset.name))
        val temp = Files.createTempFile(updatesDirectory, ".update-", ".apk.tmp")
        try {
            val request = Request.Builder().url(asset.browserDownloadUrl).build()
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) {
                    throw IOException("GitHub returned HTTP ${response.code} downloading the update.")
                }
                val body = response.body
                val expectedLength = body.contentLength().takeIf { it > 0 } ?: asset.size

                body.byteStream().use { input ->
                    Files.newOutputStream(temp).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var readTotal = 0L
                        while (true) {
                            val read = input.read(buffer)
                            if (read == -1) break
                            output.write(buffer, 0, read)
                            readTotal += read
                            if (expectedLength > 0) {
                                onProgress((readTotal.toFloat() / expectedLength).coerceIn(0f, 1f))
                            }
                        }
                        if (asset.size > 0 && readTotal != asset.size) {
                            throw IOException(
                                "Downloaded ${readTotal}B but GitHub reported ${asset.size}B — " +
                                    "the update download was incomplete."
                            )
                        }
                    }
                }
            }

            if (!looksLikeZip(temp)) {
                throw IOException("Downloaded update file is not a valid APK.")
            }

            try {
                Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
            } catch (_: Exception) {
                Files.move(temp, destination, StandardCopyOption.REPLACE_EXISTING)
            }
            onProgress(1f)
            destination
        } finally {
            Files.deleteIfExists(temp)
        }
    }

    /** Builds the system package-installer intent for an already-downloaded APK. */
    fun installIntent(apkPath: Path): Intent {
        val uri: Uri = FileProvider.getUriForFile(appContext, fileProviderAuthority, apkPath.toFile())
        return Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    private fun looksLikeZip(path: Path): Boolean {
        return runCatching {
            Files.newInputStream(path).use { input ->
                val header = ByteArray(4)
                val read = input.read(header)
                read == 4 && header.contentEquals(ZIP_MAGIC)
            }
        }.getOrDefault(false)
    }

    private fun safeFileName(name: String): String {
        val stripped = name.substringAfterLast('/').substringAfterLast('\\')
        val safe = stripped.filter { it.isLetterOrDigit() || it in ".-_" }
        return safe.ifBlank { "update.apk" }
    }
}
