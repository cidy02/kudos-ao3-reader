package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.files.ImportedFileFormat
import java.time.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** iOS WorkConversionRecord's sidecar; converter versions are independent for each app. */
@Serializable
data class WorkConversionRecord(
    val converterVersion: Int = CURRENT_VERSION,
    val format: String,
    val originalFileName: String,
    // Swift JSONEncoder's default Date: seconds since 2001-01-01, including fractions.
    val convertedAt: Double = appleDate(Instant.now()),
    val converterPlatform: String? = null
) {
    // Each app judges only its own version scale; legacy and foreign stamps ask before rebuilding.
    val isStale: Boolean get() = converterPlatform == "android" && converterVersion < CURRENT_VERSION

    fun encode(): ByteArray = json.encodeToString(this).encodeToByteArray()

    companion object {
        /** Bump here whenever Android's imported-document converters change their output. */
        const val CURRENT_VERSION = 1
        private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
        private const val APPLE_EPOCH_SECONDS = 978307200L

        fun appleDate(instant: Instant): Double =
            (instant.epochSecond - APPLE_EPOCH_SECONDS).toDouble() + instant.nano / 1_000_000_000.0

        fun decode(bytes: ByteArray?): WorkConversionRecord? = bytes?.let {
            runCatching { json.decodeFromString<WorkConversionRecord>(it.decodeToString()) }.getOrNull()
        }

        /** Without a readable Android stamp, there is no local version to judge. */
        fun isStale(record: WorkConversionRecord?): Boolean = record?.isStale ?: false

        fun formatName(format: ImportedFileFormat): String = when (format) {
            ImportedFileFormat.TEXT -> "plainText"
            else -> format.name.lowercase(java.util.Locale.ROOT)
        }
    }
}
