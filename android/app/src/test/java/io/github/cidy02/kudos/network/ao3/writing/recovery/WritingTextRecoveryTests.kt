package io.github.cidy02.kudos.network.ao3.writing.recovery

import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.FileTime
import java.time.Clock
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Shared fixture only; every test still runs on real temporary disk. */
open class RecoveryDiskFixture {
    @get:Rule val temporary = TemporaryFolder()
    protected fun makeStore(clock: Clock = advancingClock()): WritingTextRecovery =
        WritingTextRecovery(temporary.root.toPath().resolve(UUID.randomUUID().toString()), clock)
    protected fun key(store: WritingTextRecovery): Path =
        store.fileURL("writer", "work:7", "content")
    protected fun sessionURL(store: WritingTextRecovery, session: String): Path =
        key(store).resolveSibling("${key(store).fileName.toString().removeSuffix(".json")}.$session.json")
    protected fun advancingClock(): Clock = object : Clock() {
        private var next = Instant.ofEpochSecond(1_800_000_000)
        override fun getZone(): ZoneId = ZoneOffset.UTC
        override fun withZone(zone: ZoneId): Clock = this
        override fun instant(): Instant = next.also { next = next.plusSeconds(1) }
    }
}

class WritingTextEditorTests : RecoveryDiskFixture() {
    @Test fun recoveryPreservesMarkupAndSeparatesAccountsAndFields() {
        val store = makeStore()
        val url = store.fileURL("Writer", "work:17", "content")
        val markup = "<p class='custom'>A &amp; B 👩🏽‍💻</p>\n<unknown data-x='1'>keep me</unknown>"
        store.save(markup, "before", url)
        assertEquals(markup, store.load(url)?.text)
        assertEquals(WritingTextRecovery.digest("before"), store.load(url)?.originalDigest)
        assertEquals(url, store.fileURL("writer", "work:17", "content"))
        assertNotEquals(url, store.fileURL("another", "work:17", "content"))
        assertNotEquals(url, store.fileURL("Writer", "work:17", "notes"))
        store.save("", "before", url)
        assertEquals("", store.load(url)?.text)
        store.save("first composition", "", url.resolveSibling("${url.fileName.toString().removeSuffix(".json")}.first.json"))
        store.save("second composition", "", url.resolveSibling("${url.fileName.toString().removeSuffix(".json")}.second.json"))
        assertTrue(store.copies(url).map { it.entry.text }.toSet().containsAll(setOf("first composition", "second composition")))
    }
}

class WritingTextRecoveryBoundsTests : RecoveryDiskFixture() {
    @Test fun savingKeepsOnlyTheNewestFewCopiesOfAField() {
        val store = makeStore()
        val key = store.fileURL("writer", "work/42", "content")
        repeat(WritingTextRecovery.copyLimit + 4) { index ->
            store.save("draft $index", "original", store.sessionURL(key))
        }
        assertTrue(store.copies(key).size <= WritingTextRecovery.copyLimit)
    }
    @Test fun theNewestCopySurvivesPruning() {
        val store = makeStore()
        val key = store.fileURL("writer", "work/42", "content")
        var last = ""
        repeat(WritingTextRecovery.copyLimit + 2) { index ->
            last = "draft $index"
            store.save(last, "original", store.sessionURL(key))
        }
        assertEquals(last, store.copies(key).firstOrNull()?.entry?.text)
    }
}

class WritingTextRecoveryTests : RecoveryDiskFixture() {
    @Test fun fieldKeysUseUtf8ByteLengthsAndLowercaseOnlyTheAccount() {
        val store = makeStore()
        assertEquals("4aa5019c8bf8f6363a2974164027190dce48e7078525c8227d4171b0646307a2.json",
            store.fileURL("Writer", "work:17", "content").fileName.toString())
        assertEquals("d474cd553484ebfba783d253aa21708e0187b5dcc5a0d7763ecedcc406de38b6.json",
            store.fileURL("ÉCRIVAIN", "work:new", "notes").fileName.toString())
        assertEquals("da2182fa3a22efccb4030d038fd50f7af0e8b98f4997f3f3fd868d07554edf8c.json",
            store.fileURL("👩🏽‍💻", "work:7", "summary").fileName.toString())
        assertNotEquals(store.fileURL("a", "bc", "content"), store.fileURL("ab", "c", "content"))
        assertNotEquals(store.fileURL("a", "Work:7", "content"), store.fileURL("a", "work:7", "content"))
        assertNotEquals(store.fileURL("a", "work:7", "Content"), store.fileURL("a", "work:7", "content"))
        assertEquals(store.directory.resolve("WritingTextRecovery"), WritingTextRecovery.inFilesDir(store.directory).directory)
        assertEquals("${key(store).fileName.toString().removeSuffix(".json")}.ABCDEF12-3456-7890-ABCD-EF1234567890.json",
            store.sessionURL(key(store), UUID.fromString("abcdef12-3456-7890-abcd-ef1234567890")).fileName.toString())
    }

    /** Encoder-derived representative, not a captured iOS byte golden (unsorted keys have no fixed order). */
    @Test fun e1JsonUsesFoundationEpochAndDefaultStringEscaping() {
        val store = makeStore(Clock.fixed(Instant.parse("2001-01-01T00:00:00.250Z"), ZoneOffset.UTC))
        val url = sessionURL(store, "s1")
        store.save("<p>世界\n\"x\" &amp; /</p>", "before", url)
        val expected = """{"text":"<p>世界\n\"x\" &amp; \/<\/p>","originalDigest":"6db7d803e74f1ffa7d8f5adc0bf95b3e15bf4c8373fffadf546227cc6c6742cb","savedAt":0.25}"""
        assertArrayEquals(expected.toByteArray(Charsets.UTF_8), Files.readAllBytes(url))
        assertEquals(0.25, store.load(url)!!.savedAt, 0.0)
        // Foundation's decoder accepts any JSON member order.
        Files.write(url, """{"savedAt":0.25,"originalDigest":"before","text":"other"}""".toByteArray())
        assertEquals(WritingTextRecovery.Entry("other", "before", 0.25), store.load(url))
    }

    @Test fun e1DatesAcceptWholeNegativeAndFractionalSeconds() {
        for ((instant, seconds) in listOf("2001-01-01T00:00:00Z" to 0.0,
            "2000-12-31T23:59:59.750Z" to -0.25, "2026-10-05T12:00:00.125Z" to 812_894_400.125)) {
            val store = makeStore(Clock.fixed(Instant.parse(instant), ZoneOffset.UTC))
            val url = sessionURL(store, "s1")
            store.save("", "", url)
            assertEquals(seconds, store.load(url)!!.savedAt, 0.0)
        }
    }

    /** iOS has no dedicated open-filter unit test; these vectors come from loadRecoveries. */
    @Test fun openingExcludesOwnSessionAndFormTextButOffersEveryOtherReadableCopy() = runBlocking {
        val store = makeStore()
        val own = sessionURL(store, "own")
        store.save("older different", "old form", sessionURL(store, "old"))
        store.save("form", "form", sessionURL(store, "same"))
        store.save("own different", "form", own)
        store.save("newer different", "form", sessionURL(store, "new"))
        Files.write(sessionURL(store, "corrupt"), "{ broken".toByteArray())
        Files.write(sessionURL(store, "invalid-utf8"),
            "{\"text\":\"".toByteArray() + byteArrayOf(0xff.toByte()) +
                "\",\"originalDigest\":\"\",\"savedAt\":0}".toByteArray())
        val copies = store.copiesOnOpen(key(store), own, "form")
        assertEquals(listOf("newer different", "older different"), copies.map { it.entry.text })
        assertNotEquals(WritingTextRecovery.digest("form"), copies.last().entry.originalDigest)
        store.deleteCopy(copies.first())
        assertEquals(listOf("older different"), store.copiesOnOpen(key(store), own, "form").map { it.entry.text })
    }

    @Test fun missingDirectoryAndMissingCopyAreEmpty() = runBlocking {
        val store = makeStore()
        assertNull(store.load(sessionURL(store, "absent")))
        assertTrue(store.copies(key(store)).isEmpty())
        assertTrue(store.copiesOnOpen(key(store), sessionURL(store, "own"), "").isEmpty())
        assertTrue(store.allCopyURLs().isEmpty())
    }

    @Test fun openingUsesSwiftCanonicalEqualityWithoutRewritingTheSavedSource() = runBlocking {
        val store = makeStore()
        val url = sessionURL(store, "old")
        store.save("cafe\u0301", "", url)
        assertTrue(store.copiesOnOpen(key(store), sessionURL(store, "own"), "café").isEmpty())
        assertEquals("cafe\u0301", store.load(url)!!.text)
    }

    @Test fun pruningUsesFileNameToBreakModificationDateTiesAndLeavesOtherKeysAlone() {
        val store = makeStore()
        Files.createDirectories(store.directory)
        val date = FileTime.fromMillis(1_800_000_000_000)
        val files = (0..6).map { index -> sessionURL(store, "session$index").also {
            Files.write(it, "garbage".toByteArray()); Files.setLastModifiedTime(it, date)
        } }
        val other = store.sessionURL(store.fileURL("other", "work:7", "content"))
        Files.write(other, "{}".toByteArray())
        store.prune(files[0])
        // A Path is an Iterable of its own parts, so `+ other` would add those, not the file.
        assertEquals((listOf(files[0]) + files.drop(3) + listOf(other)).toSet(), store.allCopyURLs().toSet())
    }
}
