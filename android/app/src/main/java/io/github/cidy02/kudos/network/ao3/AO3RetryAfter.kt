package io.github.cidy02.kudos.network.ao3

import java.time.Duration
import java.time.Instant
import java.time.ZoneOffset
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter

object AO3RetryAfter {
    fun parseMillis(value: String?, now: Instant = Instant.now()): Long? {
        val trimmed = value?.trim().takeUnless { it.isNullOrEmpty() } ?: return null
        trimmed.toLongOrNull()
            ?.takeIf { it >= 0 }
            ?.let { return it * 1_000L }

        return runCatching {
            val retryAt = ZonedDateTime
                .parse(trimmed, DateTimeFormatter.RFC_1123_DATE_TIME)
                .withZoneSameInstant(ZoneOffset.UTC)
                .toInstant()
            Duration.between(now, retryAt).toMillis().coerceAtLeast(0)
        }.getOrNull()
    }
}
