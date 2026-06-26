package io.github.cidy02.kudos.network.ao3.work

import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.OkHttpAO3Client

class AO3EpubDownloader(
    private val client: AO3Client = OkHttpAO3Client(),
    private val urlBuilder: AO3DownloadUrlBuilder = AO3DownloadUrlBuilder()
) {
    suspend fun download(workId: Long): AO3Result<ByteArray> {
        return when (val result = client.getBytes(urlBuilder.epubDownloadUrl(workId))) {
            is AO3Result.Failure -> result
            is AO3Result.Success -> validate(result.value.body, result.value.header("Content-Type"))
        }
    }

    private fun validate(bytes: ByteArray, contentType: String?): AO3Result<ByteArray> {
        if (bytes.isEmpty()) {
            return AO3Result.Failure(AO3Error.Validation("AO3 returned an empty EPUB download."))
        }
        if (contentType?.contains("html", ignoreCase = true) == true || bytes.looksLikeHtml()) {
            return AO3Result.Failure(AO3Error.Parse("AO3 returned an HTML page instead of an EPUB."))
        }
        if (!bytes.hasZipSignature()) {
            return AO3Result.Failure(AO3Error.Validation("AO3 EPUB download did not look like a ZIP/EPUB file."))
        }
        return AO3Result.Success(bytes)
    }
}

private fun ByteArray.hasZipSignature(): Boolean {
    return size >= 4 &&
        this[0] == 0x50.toByte() &&
        this[1] == 0x4B.toByte() &&
        (this[2] == 0x03.toByte() || this[2] == 0x05.toByte() || this[2] == 0x07.toByte()) &&
        (this[3] == 0x04.toByte() || this[3] == 0x06.toByte() || this[3] == 0x08.toByte())
}

private fun ByteArray.looksLikeHtml(): Boolean {
    val preview = decodeToString(endIndex = minOf(size, 512)).trimStart()
    return preview.startsWith("<!doctype", ignoreCase = true) ||
        preview.startsWith("<html", ignoreCase = true)
}
