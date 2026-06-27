package io.github.cidy02.kudos.reader.readium

import android.content.Context
import io.github.cidy02.kudos.reader.ReaderError
import java.io.File
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.parser.DefaultPublicationParser

/** Result of opening an EPUB with Readium, mapped onto app-owned errors. */
sealed interface ReadiumOpenResult {
    data class Success(val publication: Publication) : ReadiumOpenResult
    data class Failure(val error: ReaderError) : ReadiumOpenResult
}

/**
 * Thin wrapper around Readium's streamer that opens an app-private EPUB file off
 * the main thread and maps failures to [ReaderError]. This is the only place the
 * streamer API is touched.
 */
class ReadiumPublicationOpener(context: Context) {
    private val appContext = context.applicationContext
    private val httpClient by lazy { DefaultHttpClient() }
    private val assetRetriever by lazy { AssetRetriever(appContext.contentResolver, httpClient) }
    private val opener by lazy {
        PublicationOpener(
            DefaultPublicationParser(appContext, httpClient, assetRetriever, pdfFactory = null)
        )
    }

    suspend fun open(file: File): ReadiumOpenResult = withContext(Dispatchers.IO) {
        if (!file.exists()) {
            return@withContext ReadiumOpenResult.Failure(ReaderError.FileMissing)
        }
        val asset = assetRetriever.retrieve(file).getOrNull()
            ?: return@withContext ReadiumOpenResult.Failure(
                ReaderError.OpenFailed("Could not read the EPUB container.")
            )
        val publication = opener.open(asset, allowUserInteraction = false).getOrNull()
            ?: return@withContext ReadiumOpenResult.Failure(
                ReaderError.OpenFailed("Could not open this EPUB.")
            )
        ReadiumOpenResult.Success(publication)
    }
}
