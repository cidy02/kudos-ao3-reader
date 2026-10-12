package io.github.cidy02.kudos.comments

import org.junit.Assert.assertEquals
import org.junit.Test
import java.util.Date

class CommentTimestampTest {
    private val now = Date(1_800_000_000_000)
    private fun ago(minutes: Long) = AO3CommentTimestamp.relativeNarrow(Date(now.time - minutes * 60_000), now)

    @Test fun howLongAgoInFewLetters() {
        assertEquals("now", ago(0)); assertEquals("now", ago(-5))
        assertEquals("59m ago", ago(59)); assertEquals("1h ago", ago(60)); assertEquals("23h ago", ago(23 * 60 + 59))
        assertEquals("1d ago", ago(24 * 60)); assertEquals("6d ago", ago(6 * 24 * 60))
        assertEquals("1w ago", ago(7 * 24 * 60)); assertEquals("4w ago", ago(29 * 24 * 60))
        assertEquals("3mo ago", ago(96L * 24 * 60)); assertEquals("12mo ago", ago(364L * 24 * 60))
        assertEquals("1y ago", ago(365L * 24 * 60))
    }
}
