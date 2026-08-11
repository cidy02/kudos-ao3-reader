package io.github.cidy02.kudos.backup

import kotlinx.serialization.json.Json

internal val BackupJson = Json {
    encodeDefaults = true
    explicitNulls = false
    ignoreUnknownKeys = true
    // Apple archives may omit fields that older Android manifests required.
    coerceInputValues = true
    isLenient = true
    prettyPrint = true
}
