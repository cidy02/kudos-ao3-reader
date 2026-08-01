package io.github.cidy02.kudos.data.local.converters

import androidx.room.TypeConverter
import java.time.Instant
import kotlinx.serialization.SerializationException
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json

class KudosTypeConverters {
    private val stringListSerializer = ListSerializer(String.serializer())

    @TypeConverter
    fun instantToEpochMillis(value: Instant?): Long? {
        return value?.toEpochMilli()
    }

    @TypeConverter
    fun epochMillisToInstant(value: Long?): Instant? {
        return value?.let(Instant::ofEpochMilli)
    }

    @TypeConverter
    fun stringListToJson(value: List<String>): String {
        return Json.encodeToString(stringListSerializer, value)
    }

    @TypeConverter
    fun jsonToStringList(value: String?): List<String> {
        if (value.isNullOrBlank()) return emptyList()
        return try {
            Json.decodeFromString(stringListSerializer, value)
        } catch (e: SerializationException) {
            // One row's corrupted JSON (interrupted write, format drift) must not take
            // down every query touching this column — degrade to empty rather than throw.
            emptyList()
        }
    }
}
