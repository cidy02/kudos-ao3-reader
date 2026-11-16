package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.reader.speech.PronunciationCorrections
import io.github.cidy02.kudos.works.WorkIdentityIndex
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull

@OptIn(ExperimentalSerializationApi::class)
private fun SerialDescriptor.elementNameSet(): Set<String> =
    (0 until elementsCount).mapTo(HashSet()) { getElementName(it) }

@OptIn(ExperimentalSerializationApi::class)
private val knownManifestKeys: Set<String> by lazy {
    KudosBackupManifest.serializer().descriptor.elementNameSet()
}

@OptIn(ExperimentalSerializationApi::class)
private val knownSettingsKeys: Set<String> by lazy {
    BackupSettingsPayload.serializer().descriptor.elementNameSet()
}

@OptIn(ExperimentalSerializationApi::class)
private val knownPronunciationKeys: Set<String> by lazy {
    PronunciationCorrections.serializer().descriptor.elementNameSet()
}

private val settingsMapKeys = setOf("modifiedAt", "extras")

@OptIn(ExperimentalSerializationApi::class)
private val recordListDescriptors: Map<String, SerialDescriptor> by lazy {
    mapOf(
        "works" to BackupWork.serializer().descriptor,
        "bookmarks" to BackupBookmark.serializer().descriptor,
        "fonts" to BackupFont.serializer().descriptor,
        "collections" to BackupCollection.serializer().descriptor,
        "savedSearches" to BackupSavedSearch.serializer().descriptor,
        "readingQueues" to BackupReadingQueue.serializer().descriptor,
        "readingQueueMemberships" to BackupReadingQueueMembership.serializer().descriptor,
        "annotations" to BackupAnnotation.serializer().descriptor,
        "readingSessions" to BackupReadingSession.serializer().descriptor,
        "readingFavorites" to BackupReadingFavorite.serializer().descriptor,
        "fandomReadWatermarks" to BackupFandomReadWatermark.serializer().descriptor,
        // Both apps sign fixed typed fields, not the JSON object. Extra keys do not
        // change TombstoneSigning.payloadBytes / iOS TombstoneSigning.payload(for:).
        "tombstones" to BackupTombstone.serializer().descriptor
    )
}

internal fun parseJsonObjectOrNull(bytes: ByteArray): JsonObject? {
    val text = bytes.toString(Charsets.UTF_8)
    val strict = runCatching { Json.parseToJsonElement(text) as? JsonObject }.getOrNull()
    if (strict != null) return strict
    return runCatching { BackupJson.parseToJsonElement(text) as? JsonObject }.getOrNull()
}

private fun JsonObject.text(key: String): String? =
    (get(key) as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull

private fun JsonObject.normalizedId(): String? =
    text("id")?.let(BackupPaths::normalizeIdForComparison)

private fun JsonObject.intValue(key: String): Int? =
    (get(key) as? JsonPrimitive)?.contentOrNull?.toIntOrNull()

private fun JsonObject.longValue(key: String): Long? =
    (get(key) as? JsonPrimitive)?.contentOrNull?.toLongOrNull()

private fun JsonObject.favoriteTarget(): Pair<String, String>? {
    val kind = text("kindRaw") ?: return null
    return text("targetKey")?.let { kind to it }
}

private class RecordMatcher(
    private val listName: String,
    private val candidates: List<JsonObject>
) {
    private val byId = candidates.mapNotNull { record -> record.normalizedId()?.let { it to record } }.toMap()
    private val workIndex = if (listName == "works") {
        WorkIdentityIndex.snapshot(
            candidates.mapNotNull { record ->
                record.normalizedId()?.let { id ->
                    SavedWork(
                        id = id,
                        title = "",
                        author = "",
                        sourceUrl = record.text("sourceURL").orEmpty(),
                        ao3WorkID = record.intValue("ao3WorkID"),
                        hasEpub = false
                    )
                }
            }
        )
    } else {
        null
    }
    private val byUrl = if (listName == "bookmarks") candidates.associateBy { it.text("urlString") } else emptyMap()
    private val byFont = if (listName == "fonts") {
        candidates.groupBy { it.text("fileName")?.let(BackupPaths::fontFileNameKey) }
    } else {
        emptyMap()
    }
    private val byFandom = if (listName == "fandomReadWatermarks") {
        candidates.associateBy { it.text("fandomName") }
    } else {
        emptyMap()
    }
    private val byTarget = if (listName == "readingFavorites") {
        candidates.associateBy { it.favoriteTarget() }
    } else {
        emptyMap()
    }

    fun match(record: JsonObject): JsonObject? = when (listName) {
        "works" -> workIndex?.existingWork(
            ao3WorkId = record.longValue("ao3WorkID"),
            sourceUrl = record.text("sourceURL"),
            recordId = record.normalizedId()
        )?.let { byId[BackupPaths.normalizeIdForComparison(it.id)] }
        "bookmarks" -> record.text("urlString")?.let { byUrl[it] } ?: record.normalizedId()?.let { byId[it] }
        "fonts" -> record.text("fileName")?.let { name ->
            val matches = byFont[BackupPaths.fontFileNameKey(name)].orEmpty()
            matches.firstOrNull { it.text("fileName") == name } ?: matches.singleOrNull()
        }
        "fandomReadWatermarks" -> record.normalizedId()?.let { byId[it] }
            ?: record.text("fandomName")?.let { byFandom[it] }
        "readingFavorites" -> record.normalizedId()?.let { byId[it] }
            ?: record.favoriteTarget()?.let { byTarget[it] }
        "readingQueues" -> if (record.text("kindRaw") == ReadingQueueKind.SAVED_FOR_LATER) {
            candidates.firstOrNull { it.text("kindRaw") == ReadingQueueKind.SAVED_FOR_LATER }
                ?: record.normalizedId()?.let { byId[it] }
        } else {
            record.normalizedId()?.let { byId[it] }
        }
        else -> record.normalizedId()?.let { byId[it] }
    }
}

private fun mergeJsonObjectWithMaps(
    outgoing: JsonObject,
    replaced: JsonObject,
    knownKeys: Set<String>,
    mapKeys: Set<String>
): JsonObject {
    val merged = linkedMapOf<String, JsonElement>()
    merged.putAll(outgoing)
    mapKeys.forEach { mapKey ->
        val oldVal = replaced[mapKey]
        val newVal = outgoing[mapKey]
        if (newVal is JsonObject && oldVal is JsonObject) {
            merged[mapKey] = JsonObject(oldVal + newVal)
        } else if (newVal == null && oldVal != null) {
            merged[mapKey] = oldVal
        }
    }
    replaced.forEach { (key, value) ->
        if (key !in knownKeys && key !in mapKeys && key !in merged) {
            merged[key] = value
        }
    }
    return JsonObject(merged)
}

/**
 * Carries unmodeled fields from [replaced] into [outgoing] across all manifest levels:
 * top-level unknown keys/arrays, `settings` (including `modifiedAt` and `extras` map entries),
 * `pronunciations` (including `stamps`), and every record list Android writes.
 * Records absent from [outgoing] (deleted) are never resurrected.
 */
@OptIn(ExperimentalSerializationApi::class)
internal fun carryUnknownRecordKeys(outgoing: JsonObject, replaced: JsonObject?): JsonObject {
    if (replaced == null) return outgoing

    val result = outgoing.toMutableMap()

    val oldSettings = replaced["settings"] as? JsonObject
    val newSettings = outgoing["settings"] as? JsonObject
    if (oldSettings != null && newSettings != null) {
        result["settings"] = mergeJsonObjectWithMaps(
            outgoing = newSettings,
            replaced = oldSettings,
            knownKeys = knownSettingsKeys,
            mapKeys = settingsMapKeys
        )
    }

    val oldPronunciations = replaced["pronunciations"] as? JsonObject
    val newPronunciations = outgoing["pronunciations"] as? JsonObject
    if (oldPronunciations != null && newPronunciations != null) {
        result["pronunciations"] = mergeJsonObjectWithMaps(
            outgoing = newPronunciations,
            replaced = oldPronunciations,
            knownKeys = knownPronunciationKeys,
            mapKeys = setOf("stamps")
        )
    }

    recordListDescriptors.forEach { (listName, descriptor) ->
        val oldRecords = (replaced[listName] as? JsonArray)?.mapNotNull { it as? JsonObject }
            ?: return@forEach
        val newRecords = outgoing[listName] as? JsonArray ?: return@forEach
        val known = descriptor.elementNameSet()
        val matcher = RecordMatcher(listName, oldRecords)
        result[listName] = JsonArray(
            newRecords.map { element ->
                val record = element as? JsonObject ?: return@map element
                val old = matcher.match(record) ?: return@map record
                JsonObject(record + old.filterKeys { it !in known && it !in record })
            }
        )
    }

    replaced.forEach { (key, value) ->
        if (key !in knownManifestKeys && key !in result) {
            result[key] = value
        }
    }
    return JsonObject(result)
}

/**
 * Folds a conflict manifest's raw JSON ([fallback]) beneath the primary manifest ([primary])
 * so unknown keys/records introduced by a folded conflict survive until commit.
 */
internal fun mergeFallbackManifestJson(primary: JsonObject?, fallback: JsonObject?): JsonObject? {
    if (primary == null) return fallback
    if (fallback == null) return primary

    val merged = linkedMapOf<String, JsonElement>()
    merged.putAll(primary)

    val primarySettings = primary["settings"] as? JsonObject
    val fallbackSettings = fallback["settings"] as? JsonObject
    if (primarySettings != null && fallbackSettings != null) {
        val combined = linkedMapOf<String, JsonElement>()
        combined.putAll(primarySettings)
        settingsMapKeys.forEach { mapKey ->
            val pVal = primarySettings[mapKey]
            val fVal = fallbackSettings[mapKey]
            if (pVal is JsonObject && fVal is JsonObject) {
                combined[mapKey] = JsonObject(fVal + pVal)
            } else if (pVal == null && fVal != null) {
                combined[mapKey] = fVal
            }
        }
        fallbackSettings.forEach { (key, value) ->
            if (key !in settingsMapKeys && key !in combined) {
                combined[key] = value
            }
        }
        merged["settings"] = JsonObject(combined)
    }

    val primaryPron = primary["pronunciations"] as? JsonObject
    val fallbackPron = fallback["pronunciations"] as? JsonObject
    if (primaryPron != null && fallbackPron != null) {
        val combined = linkedMapOf<String, JsonElement>()
        combined.putAll(primaryPron)
        val pStamps = primaryPron["stamps"]
        val fStamps = fallbackPron["stamps"]
        if (pStamps is JsonObject && fStamps is JsonObject) {
            combined["stamps"] = JsonObject(fStamps + pStamps)
        } else if (pStamps == null && fStamps != null) {
            combined["stamps"] = fStamps
        }
        fallbackPron.forEach { (key, value) ->
            if (key != "stamps" && key !in combined) {
                combined[key] = value
            }
        }
        merged["pronunciations"] = JsonObject(combined)
    }

    recordListDescriptors.keys.forEach { listName ->
        val pArray = primary[listName] as? JsonArray
        val fArray = fallback[listName] as? JsonArray
        if (pArray != null && fArray != null) {
            val fObjects = fArray.mapNotNull { it as? JsonObject }
            val matcher = RecordMatcher(listName, fObjects)
            val fallbackIndexByIdentity = java.util.IdentityHashMap<JsonObject, Int>()
            fObjects.forEachIndexed { index, obj -> fallbackIndexByIdentity[obj] = index }
            val matchedFallbackIndices = hashSetOf<Int>()
            val combined = pArray.map { element ->
                val pObj = element as? JsonObject ?: return@map element
                val match = matcher.match(pObj) ?: return@map pObj
                fallbackIndexByIdentity[match]?.let { matchedFallbackIndices += it }
                JsonObject(match + pObj)
            } + fObjects.filterIndexed { index, _ -> index !in matchedFallbackIndices }
            merged[listName] = JsonArray(combined)
        } else if ((primary[listName] == null || primary[listName] is JsonNull) && fArray != null) {
            merged[listName] = fArray
        }
    }

    fallback.forEach { (key, value) ->
        if (key !in knownManifestKeys && key !in merged) {
            merged[key] = value
        }
    }
    return JsonObject(merged)
}

/**
 * Persists the raw JSON of the last-read sync manifest next to existing sync/file state so
 * commit-time sync-up can carry unmodeled fields even across fallback recoveries or crashes.
 */
internal class SyncLastManifestStore(
    directory: Path,
    fileName: String = "sync-last-manifest.json"
) {
    val file: Path = directory.resolve(fileName)
    private val lock = Any()

    fun load(): JsonObject? = synchronized(lock) {
        if (!Files.isRegularFile(file)) return null
        val bytes = runCatching { Files.readAllBytes(file) }.getOrNull() ?: return null
        parseJsonObjectOrNull(bytes)
    }

    fun save(json: JsonObject) {
        val bytes = BackupJson.encodeToString(JsonObject.serializer(), json).toByteArray(Charsets.UTF_8)
        save(bytes)
    }

    fun save(bytes: ByteArray) = synchronized(lock) {
        val parent = file.parent
        if (parent != null) Files.createDirectories(parent)
        val temp = Files.createTempFile(parent, ".sync-last-manifest-", ".tmp")
        try {
            Files.write(temp, bytes)
            try {
                Files.move(temp, file, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (_: Exception) {
                Files.move(temp, file, StandardCopyOption.REPLACE_EXISTING)
            }
        } finally {
            runCatching { Files.deleteIfExists(temp) }
        }
    }

    fun clear() = synchronized(lock) {
        runCatching { Files.deleteIfExists(file) }
        Unit
    }
}
