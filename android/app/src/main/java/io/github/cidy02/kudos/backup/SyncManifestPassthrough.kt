package io.github.cidy02.kudos.backup

import io.github.cidy02.kudos.core.model.ReadingQueueKind
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.reader.speech.PronunciationCorrections
import io.github.cidy02.kudos.works.WorkIdentityIndex
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.time.OffsetDateTime
import java.time.temporal.ChronoUnit
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
 * One raw manifest among the live file, its `.bak`, and SAF conflict copies.
 * [modifiedAtMillis] is the file's own modification time. [liveName] is the real
 * `manifest.json`, used only to break a tie.
 */
internal data class RawManifestCopy(
    val json: JsonObject,
    val modifiedAtMillis: Long,
    val liveName: Boolean
) {
    val exportedAt: Instant?
        get() = instantOf(json["exportedAt"])
}

/**
 * Picks the newest copy by `exportedAt`, then file modification time, then the live
 * name, and folds the others under it. A missing `exportedAt` sorts as the epoch, so
 * a dated file outranks an undated one.
 */
internal fun foldManifestCopies(copies: List<RawManifestCopy>): JsonObject? {
    if (copies.isEmpty()) return null
    val ranked = copies.sortedWith(
        compareByDescending<RawManifestCopy> { it.exportedAt ?: Instant.EPOCH }
            .thenByDescending { it.modifiedAtMillis }
            .thenByDescending { if (it.liveName) 1 else 0 }
    )
    var merged = ranked.first().json
    ranked.drop(1).forEach { copy ->
        merged = mergeFallbackManifestJson(merged, copy.json) ?: merged
    }
    return merged
}

/**
 * Merges a newly imported manifest with the existing stored manifest, picking the strictly
 * newer `exportedAt` as primary. Ties or a missing `exportedAt` favour [incoming].
 */
internal fun mergeImportedManifestJson(incoming: JsonObject, existing: JsonObject?): JsonObject {
    if (existing == null) return incoming
    val incomingAt = instantOf(incoming["exportedAt"])
    val existingAt = instantOf(existing["exportedAt"])
    val existingIsStrictlyNewer = incomingAt != null && existingAt != null && existingAt > incomingAt
    val primary = if (existingIsStrictlyNewer) existing else incoming
    val fallback = if (existingIsStrictlyNewer) incoming else existing
    return mergeFallbackManifestJson(primary, fallback) ?: primary
}

/**
 * Folds [fallback] beneath [primary]. A key [primary] merely lacks is kept, including
 * writing drafts. A newer `modifiedAt` / record stamp is the only removal: the side
 * with the strictly newer stamp supplies that extras entry or the whole record, and
 * an older stamp does not overwrite a newer one. Equal stamps do not apply.
 * Each side's stamps are bounded by that manifest's `exportedAt`.
 */
internal fun mergeFallbackManifestJson(
    primary: JsonObject?,
    fallback: JsonObject?,
    now: Instant = Instant.now()
): JsonObject? {
    if (primary == null) return fallback
    if (fallback == null) return primary

    val primaryBounds = StampBounds(instantOf(primary["exportedAt"]), now)
    val fallbackBounds = StampBounds(instantOf(fallback["exportedAt"]), now)
    val merged = linkedMapOf<String, JsonElement>()
    merged.putAll(primary)

    val primarySettings = primary["settings"] as? JsonObject
    val fallbackSettings = fallback["settings"] as? JsonObject
    if (primarySettings != null || fallbackSettings != null) {
        val existingSettings = primary["settings"]
        if (existingSettings == null || existingSettings is JsonNull || existingSettings is JsonObject) {
            merged["settings"] = mergeStampedSettings(
                primarySettings ?: JsonObject(emptyMap()),
                fallbackSettings ?: JsonObject(emptyMap()),
                primaryBounds,
                fallbackBounds
            )
        }
    }

    val primaryPron = primary["pronunciations"] as? JsonObject
    val fallbackPron = fallback["pronunciations"] as? JsonObject
    if (primaryPron != null || fallbackPron != null) {
        val existingPron = primary["pronunciations"]
        if (existingPron == null || existingPron is JsonNull || existingPron is JsonObject) {
            merged["pronunciations"] = mergeStampedPronunciations(
                primaryPron ?: JsonObject(emptyMap()),
                fallbackPron ?: JsonObject(emptyMap()),
                primaryBounds,
                fallbackBounds
            )
        }
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
                val match = matcher.match(pObj)
                if (match == null) {
                    withBoundedRecordStamps(listName, pObj, primaryBounds)
                } else {
                    fallbackIndexByIdentity[match]?.let { matchedFallbackIndices += it }
                    mergeRawRecord(listName, pObj, match, primaryBounds, fallbackBounds)
                }
            } + fObjects.filterIndexed { index, _ -> index !in matchedFallbackIndices }
                .map { withBoundedRecordStamps(listName, it, fallbackBounds) }
            merged[listName] = JsonArray(combined)
        } else if ((primary[listName] == null || primary[listName] is JsonNull) && fArray != null) {
            merged[listName] = JsonArray(
                fArray.map { element ->
                    val obj = element as? JsonObject ?: return@map element
                    withBoundedRecordStamps(listName, obj, fallbackBounds)
                }
            )
        } else if (pArray != null) {
            merged[listName] = JsonArray(
                pArray.map { element ->
                    val obj = element as? JsonObject ?: return@map element
                    withBoundedRecordStamps(listName, obj, primaryBounds)
                }
            )
        }
    }

    // Includes known objects the primary omitted, so a partial conflict cannot drop settings.
    fallback.forEach { (key, value) ->
        if (key !in merged) merged[key] = value
    }
    return JsonObject(merged)
}

private enum class StampWinner { PRIMARY, FALLBACK, TIE }

private data class EntryStamp(val stampKey: String, val owner: String, val entry: String)

internal fun instantOf(element: JsonElement?): Instant? {
    val text = (element as? JsonPrimitive)?.contentOrNull ?: return null
    return runCatching { Instant.parse(text) }.getOrNull()
        ?: runCatching { OffsetDateTime.parse(text).toInstant() }.getOrNull()
}

/**
 * One manifest's clock for stamp comparisons. [exportedAt] is that file's own
 * `exportedAt`; a missing or far-future value does not cap.
 */
private class StampBounds(val exportedAt: Instant?, val now: Instant) {
    fun of(element: JsonElement?): Instant? = boundedInstant(element, exportedAt, now)
}

/**
 * Ignores an instant more than 24h ahead of [now]. Caps every other instant at
 * [exportedAt] when that cap is itself inside the same window, matching
 * [BackupValidator.parseInstant].
 */
private fun boundedInstant(element: JsonElement?, exportedAt: Instant?, now: Instant): Instant? {
    val parsed = instantOf(element) ?: return null
    val limit = now.plus(24, ChronoUnit.HOURS)
    if (parsed.isAfter(limit)) return null
    val cap = exportedAt?.takeUnless { it.isAfter(limit) }
    return if (cap != null && parsed.isAfter(cap)) cap else parsed
}

/**
 * Returns [element] bounded by [bounds] when serialized into a merged manifest, so a
 * fallback record or stamp cannot keep an uncapped timestamp under a newer primary's
 * `exportedAt`. Non-date values stay verbatim; instants past `now + 24h` are dropped.
 */
private fun cappedStamp(element: JsonElement?, bounds: StampBounds): JsonElement? {
    if (element == null) return null
    val raw = instantOf(element) ?: return element
    val bounded = bounds.of(element) ?: return null
    return if (bounded == raw) element else JsonPrimitive(BackupValidator.formatInstant(bounded))
}

/**
 * Record modification stamp: `readingQueues` use `max(dateUpdated, lastMembershipChangedAt)`;
 * other lists use `lastModifiedAt` or a primitive `modifiedAt`, with creation-date fallbacks
 * for collections (`dateAdded`), memberships (`queuedAt`), and annotations (`createdAt`).
 * Every candidate is passed through [boundedInstant].
 */
private fun recordStamp(listName: String, record: JsonObject, bounds: StampBounds): Instant? {
    fun at(element: JsonElement?) = bounds.of(element)
    if (listName == "readingQueues") {
        listOfNotNull(
            at(record["dateUpdated"]),
            at(record["lastMembershipChangedAt"])
        ).maxOrNull()?.let { return it }
    }
    val lastModified = record["lastModifiedAt"]
    if (lastModified != null) {
        at(lastModified)?.let { return it }
        // A present-but-rejected future clock must not fall back to creation dates.
        if (instantOf(lastModified) != null) return null
    }
    val modified = record["modifiedAt"]
    if (modified != null && modified !is JsonObject && modified !is JsonArray) {
        at(modified)?.let { return it }
    }
    return when (listName) {
        "collections" -> at(record["dateAdded"])
        "readingQueueMemberships" -> at(record["queuedAt"])
        "annotations" -> at(record["createdAt"])
        else -> null
    }
}

private fun stampKeysForRecord(listName: String): List<String> = buildList {
    if (listName == "readingQueues") {
        add("dateUpdated")
        add("lastMembershipChangedAt")
    }
    add("lastModifiedAt")
    add("modifiedAt")
    when (listName) {
        "collections" -> add("dateAdded")
        "readingQueueMemberships" -> add("queuedAt")
        "annotations" -> add("createdAt")
    }
}

private fun withBoundedRecordStamps(
    listName: String,
    record: JsonObject,
    bounds: StampBounds
): JsonObject {
    var updated: MutableMap<String, JsonElement>? = null
    stampKeysForRecord(listName).forEach { key ->
        val value = record[key] ?: return@forEach
        if (key == "modifiedAt" && (value is JsonObject || value is JsonArray)) return@forEach
        val bounded = cappedStamp(value, bounds)
        if (bounded != value) {
            val map = updated ?: record.toMutableMap().also { updated = it }
            if (bounded == null) map.remove(key) else map[key] = bounded
        }
    }
    return updated?.let(::JsonObject) ?: record
}

/** A real stamp beats a missing one. Equal instants are a tie: the incoming date must be greater. */
private fun stampWinner(primary: Instant?, fallback: Instant?): StampWinner = when {
    primary == null && fallback == null -> StampWinner.TIE
    primary == null -> StampWinner.FALLBACK
    fallback == null -> StampWinner.PRIMARY
    primary > fallback -> StampWinner.PRIMARY
    fallback > primary -> StampWinner.FALLBACK
    else -> StampWinner.TIE
}

/** iOS `SyncedSettingsClock.entryID`: a JSON array of two strings, `["owner","entry"]`. */
private fun settingsEntryId(stampKey: String): Pair<String, String>? {
    if (!stampKey.startsWith("[")) return null
    val array = runCatching { BackupJson.parseToJsonElement(stampKey) }.getOrNull() as? JsonArray
        ?: return null
    if (array.size != 2) return null
    val owner = array[0] as? JsonPrimitive ?: return null
    val entry = array[1] as? JsonPrimitive ?: return null
    if (!owner.isString || !entry.isString) return null
    return owner.content to entry.content
}

/** Comment-draft shape only: `{"map": { ... }}`. Anything else stays one extras value. */
private fun mapBody(value: JsonElement?): JsonObject? {
    val obj = value as? JsonObject ?: return null
    if (obj.keys != setOf("map")) return null
    return obj["map"] as? JsonObject
}

/**
 * The winning side supplies the stamp and the value. A winning stamp with no value is a
 * removal. A tie keeps the primary value when it has one.
 */
private fun applyStampedValue(
    primaryStamp: JsonElement?,
    fallbackStamp: JsonElement?,
    primaryValue: JsonElement?,
    fallbackValue: JsonElement?,
    primaryBounds: StampBounds,
    fallbackBounds: StampBounds,
    onStamp: (JsonElement) -> Unit,
    onValue: (JsonElement) -> Unit
) {
    when (stampWinner(primaryBounds.of(primaryStamp), fallbackBounds.of(fallbackStamp))) {
        StampWinner.PRIMARY -> {
            cappedStamp(primaryStamp, primaryBounds)?.let(onStamp)
            primaryValue?.let(onValue)
        }
        StampWinner.FALLBACK -> {
            cappedStamp(fallbackStamp, fallbackBounds)?.let(onStamp)
            fallbackValue?.let(onValue)
        }
        StampWinner.TIE -> {
            (cappedStamp(primaryStamp, primaryBounds) ?: cappedStamp(fallbackStamp, fallbackBounds))?.let(onStamp)
            (primaryValue ?: fallbackValue)?.let(onValue)
        }
    }
}

private fun mergeStampedSettings(
    primary: JsonObject,
    fallback: JsonObject,
    primaryBounds: StampBounds,
    fallbackBounds: StampBounds
): JsonObject {
    val combined = linkedMapOf<String, JsonElement>()
    combined.putAll(primary)
    fallback.forEach { (key, value) ->
        if (key != "modifiedAt" && key != "extras" && key !in combined) combined[key] = value
    }

    val pMod = primary["modifiedAt"] as? JsonObject
    val fMod = fallback["modifiedAt"] as? JsonObject
    val pExtras = primary["extras"] as? JsonObject
    val fExtras = fallback["extras"] as? JsonObject
    if (pMod == null && fMod == null && pExtras == null && fExtras == null) {
        return JsonObject(combined)
    }

    val pModMap = pMod ?: JsonObject(emptyMap())
    val fModMap = fMod ?: JsonObject(emptyMap())
    val pExtrasMap = pExtras ?: JsonObject(emptyMap())
    val fExtrasMap = fExtras ?: JsonObject(emptyMap())
    val mergedMod = linkedMapOf<String, JsonElement>()
    val mergedExtras = linkedMapOf<String, JsonElement>()
    val handledMod = hashSetOf<String>()
    val entryIds = (pModMap.keys + fModMap.keys).mapNotNull { key ->
        settingsEntryId(key)?.let { (owner, entry) -> EntryStamp(key, owner, entry) }
    }
    val owners = (pExtrasMap.keys + fExtrasMap.keys + entryIds.map { it.owner }).toSet()

    owners.forEach { owner ->
        val pValue = pExtrasMap[owner]
        val fValue = fExtrasMap[owner]
        val ownerEntries = entryIds.filter { it.owner == owner }
        val ownerStamp = pModMap[owner] ?: fModMap[owner]
        val ownerWinner = stampWinner(primaryBounds.of(pModMap[owner]), fallbackBounds.of(fModMap[owner]))
        val mapOwner = mapBody(pValue) != null || mapBody(fValue) != null || ownerEntries.isNotEmpty()
        if (!mapOwner) {
            applyStampedValue(
                primaryStamp = pModMap[owner],
                fallbackStamp = fModMap[owner],
                primaryValue = pValue,
                fallbackValue = fValue,
                primaryBounds = primaryBounds,
                fallbackBounds = fallbackBounds,
                onStamp = { mergedMod[owner] = it },
                onValue = { mergedExtras[owner] = it }
            )
            if (ownerStamp != null) handledMod += owner
            return@forEach
        }
        // An owner-level stamp with no per-entry stamps dates the whole extra.
        if (ownerEntries.isEmpty() && ownerStamp != null && ownerWinner != StampWinner.TIE) {
            applyStampedValue(
                primaryStamp = pModMap[owner],
                fallbackStamp = fModMap[owner],
                primaryValue = pValue,
                fallbackValue = fValue,
                primaryBounds = primaryBounds,
                fallbackBounds = fallbackBounds,
                onStamp = { mergedMod[owner] = it },
                onValue = { mergedExtras[owner] = it }
            )
            handledMod += owner
            return@forEach
        }
        val pMap = mapBody(pValue)
        val fMap = mapBody(fValue)
        val entries = (pMap?.keys.orEmpty() + fMap?.keys.orEmpty() + ownerEntries.map { it.entry }).toSet()
        val mergedMap = linkedMapOf<String, JsonElement>()
        entries.forEach { entry ->
            val stamp = ownerEntries.firstOrNull { it.entry == entry }
            val stampKey = stamp?.stampKey
            applyStampedValue(
                primaryStamp = stampKey?.let { pModMap[it] },
                fallbackStamp = stampKey?.let { fModMap[it] },
                primaryValue = pMap?.get(entry),
                fallbackValue = fMap?.get(entry),
                primaryBounds = primaryBounds,
                fallbackBounds = fallbackBounds,
                onStamp = { if (stampKey != null) mergedMod[stampKey] = it },
                onValue = { mergedMap[entry] = it }
            )
            if (stampKey != null) handledMod += stampKey
        }
        if (mergedMap.isNotEmpty()) {
            mergedExtras[owner] = JsonObject(mapOf("map" to JsonObject(mergedMap)))
        }
    }

    (pModMap.keys + fModMap.keys).forEach { key ->
        if (key in handledMod) return@forEach
        applyStampedValue(
            primaryStamp = pModMap[key],
            fallbackStamp = fModMap[key],
            primaryValue = null,
            fallbackValue = null,
            primaryBounds = primaryBounds,
            fallbackBounds = fallbackBounds,
            onStamp = { mergedMod[key] = it },
            onValue = { _ -> }
        )
    }

    if (pMod != null || fMod != null) combined["modifiedAt"] = JsonObject(mergedMod)
    if (pExtras != null || fExtras != null) combined["extras"] = JsonObject(mergedExtras)
    return JsonObject(combined)
}

private fun mergeStampedPronunciations(
    primary: JsonObject,
    fallback: JsonObject,
    primaryBounds: StampBounds,
    fallbackBounds: StampBounds
): JsonObject {
    val combined = linkedMapOf<String, JsonElement>()
    combined.putAll(primary)
    val pStamps = primary["stamps"] as? JsonObject
    val fStamps = fallback["stamps"] as? JsonObject
    if (pStamps != null || fStamps != null) {
        val mergedStamps = linkedMapOf<String, JsonElement>()
        (pStamps?.keys.orEmpty() + fStamps?.keys.orEmpty()).forEach { key ->
            applyStampedValue(
                primaryStamp = pStamps?.get(key),
                fallbackStamp = fStamps?.get(key),
                primaryValue = null,
                fallbackValue = null,
                primaryBounds = primaryBounds,
                fallbackBounds = fallbackBounds,
                onStamp = { mergedStamps[key] = it },
                onValue = { _ -> }
            )
        }
        combined["stamps"] = JsonObject(mergedStamps)
    }
    fallback.forEach { (key, value) ->
        if (key !in combined) combined[key] = value
    }
    return JsonObject(combined)
}

/**
 * The newer record stamp wins the whole record, so a key that record omits stays removed.
 * No stamp, or a tie, keeps keys that only one side has and lets the primary overwrite collisions.
 */
private fun mergeRawRecord(
    listName: String,
    primary: JsonObject,
    fallback: JsonObject,
    primaryBounds: StampBounds,
    fallbackBounds: StampBounds
): JsonObject {
    return when (
        stampWinner(
            recordStamp(listName, primary, primaryBounds),
            recordStamp(listName, fallback, fallbackBounds)
        )
    ) {
        StampWinner.PRIMARY -> withBoundedRecordStamps(listName, primary, primaryBounds)
        StampWinner.FALLBACK -> withBoundedRecordStamps(listName, fallback, fallbackBounds)
        StampWinner.TIE -> JsonObject(
            withBoundedRecordStamps(listName, fallback, fallbackBounds) +
                withBoundedRecordStamps(listName, primary, primaryBounds)
        )
    }
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

    /** Older builds kept the folder tag in this sibling file. Read once, deleted after the first single-file save. */
    private val legacyFolderFile: Path = directory.resolve("$fileName.folder")

    /** The body and the folder tag live in one file so one atomic move publishes both. */
    private class Stored(val body: JsonObject, val folder: String?, val enveloped: Boolean, val generation: String?)

    private fun read(): Stored? {
        if (!Files.isRegularFile(file)) return null
        val bytes = runCatching { Files.readAllBytes(file) }.getOrNull() ?: return null
        val obj = parseJsonObjectOrNull(bytes) ?: return null
        val body = obj[ENVELOPE_BODY] as? JsonObject
        if (body != null) {
            return Stored(
                body,
                (obj[ENVELOPE_FOLDER] as? JsonPrimitive)?.contentOrNull,
                enveloped = true,
                generation = (obj[ENVELOPE_GENERATION] as? JsonPrimitive)?.contentOrNull
            )
        }
        return Stored(obj, readLegacyTag(), enveloped = false, generation = null)
    }

    private fun readLegacyTag(): String? {
        if (!Files.isRegularFile(legacyFolderFile)) return null
        return runCatching { Files.readAllBytes(legacyFolderFile).toString(Charsets.UTF_8) }.getOrNull()
    }

    fun load(): JsonObject? = synchronized(lock) { read()?.body }

    /** The Replace generation this file was published under, if any. */
    fun generation(): String? = synchronized(lock) { read()?.generation }

    /** Rewrites a legacy body + `.folder` pair as one envelope, so a copy of the file carries its tag. */
    fun normalizeLegacy() = synchronized(lock) {
        val stored = read() ?: return@synchronized
        if (!stored.enveloped) save(stored.body, folderUri = stored.folder)
    }

    fun taggedFolderUri(): String? = synchronized(lock) { read()?.folder }

    fun belongsToFolder(folderUri: String): Boolean = synchronized(lock) {
        taggedFolderUri() == folderUri
    }

    /**
     * Load, transform and save in one critical section, so no other save can land between
     * the read and the write.
     */
    fun update(
        folderUri: String? = null,
        clearStaleFolderTag: Boolean = false,
        transform: (JsonObject?) -> JsonObject
    ) = synchronized(lock) { save(transform(load()), folderUri, clearStaleFolderTag) }

    /**
     * [folderUri] non-null tags the file with it. Null keeps the tag already stored, unless
     * [clearStaleFolderTag] asks for it to be dropped in the same publish.
     */
    fun save(
        json: JsonObject,
        folderUri: String? = null,
        clearStaleFolderTag: Boolean = false,
        generation: String? = null
    ) = synchronized(lock) {
        val tag = when {
            folderUri != null -> folderUri
            clearStaleFolderTag -> null
            else -> taggedFolderUri()
        }
        val envelope = JsonObject(
            buildMap {
                if (tag != null) put(ENVELOPE_FOLDER, JsonPrimitive(tag))
                if (generation != null) put(ENVELOPE_GENERATION, JsonPrimitive(generation))
                put(ENVELOPE_BODY, json)
            }
        )
        publish(BackupJson.encodeToString(JsonObject.serializer(), envelope).toByteArray(Charsets.UTF_8))
    }

    /** Raw manifest bytes, tagged or untagged exactly as [json] would be. */
    fun save(
        bytes: ByteArray,
        folderUri: String? = null,
        clearStaleFolderTag: Boolean = false
    ) {
        val body = parseJsonObjectOrNull(bytes) ?: return
        save(body, folderUri, clearStaleFolderTag)
    }

    private fun publish(bytes: ByteArray) = synchronized(lock) {
        // Inside the lock, before the file is replaced, so a clear on any instance
        // cannot finish until this publish does, and cannot be overwritten by it.
        beforeFilePublish?.invoke(file)
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
        // Only after the single-file move succeeded: the tag is inside it now.
        runCatching { Files.deleteIfExists(legacyFolderFile) }
        Unit
    }

    fun clear() = synchronized(lock) {
        runCatching { Files.deleteIfExists(file) }
        runCatching { Files.deleteIfExists(legacyFolderFile) }
        Unit
    }

    internal companion object {
        private val lock = Any()
        private const val ENVELOPE_FOLDER = "kudosStoreFolder"
        private const val ENVELOPE_BODY = "kudosStoreManifest"
        private const val ENVELOPE_GENERATION = "kudosStoreGeneration"

        /** Test hook. Receives the file about to be published. Null in production. */
        internal var beforeFilePublish: ((Path) -> Unit)? = null
    }
}
