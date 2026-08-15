package io.github.cidy02.kudos.backup

import com.google.crypto.tink.subtle.Ed25519Sign
import io.github.cidy02.kudos.core.model.SyncTombstone
import io.github.cidy02.kudos.core.model.SyncTombstoneRecordType
import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TombstoneSigningTest {
    @Test
    fun payloadIsNewlineJoinedFieldsWithoutTrailingNewline() {
        val tombstone = SyncTombstone(
            recordID = "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA",
            recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
            createdAt = Instant.parse("2026-08-15T16:00:00.123Z"),
            lastModifiedAt = Instant.parse("2026-08-15T16:00:00.123Z"),
            sourceURL = "https://www.archiveofourown.org/works/123/chapters/9",
            ao3WorkID = 123,
            signerPublicKey = "ab".repeat(32)
        )
        val payload = TombstoneSigning.payloadUtf8(tombstone)
        assertEquals(
            listOf(
                "savedWork",
                "123",
                "https://archiveofourown.org/works/123",
                "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                "2026-08-15T16:00:00Z",
                "ab".repeat(32)
            ).joinToString("\n"),
            payload
        )
        assertFalse(payload.endsWith("\n"))
    }

    @Test
    fun emptyAo3AndNonAo3UrlAreEmptyPayloadFields() {
        val tombstone = SyncTombstone(
            recordID = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
            recordTypeRaw = SyncTombstoneRecordType.WORK_COLLECTION,
            createdAt = Instant.parse("2026-08-15T16:00:00Z"),
            signerPublicKey = "cd".repeat(32)
        )
        assertEquals(
            listOf(
                "workCollection",
                "",
                "",
                "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                "2026-08-15T16:00:00Z",
                "cd".repeat(32)
            ).joinToString("\n"),
            TombstoneSigning.payloadUtf8(tombstone)
        )
    }

    @Test
    fun signThenVerifyRoundTrip() {
        val pair = Ed25519Sign.KeyPair.newKeyPair()
        val pub = pair.publicKey.toLowerHex()
        val signed = TombstoneSigning.signWithRawKey(
            SyncTombstone(
                recordID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc",
                recordTypeRaw = SyncTombstoneRecordType.SAVED_WORK,
                createdAt = Instant.parse("2026-08-15T16:00:00Z"),
                sourceURL = "https://archiveofourown.org/works/42",
                ao3WorkID = 42
            ),
            pair.privateKey,
            pub
        )
        assertEquals(64, signed.signerPublicKey.length)
        assertEquals(128, signed.signature.length)
        assertTrue(TombstoneSigning.verify(signed))
        assertFalse(TombstoneSigning.verify(signed.copy(signature = "")))
        assertFalse(TombstoneSigning.verify(signed.copy(signature = signed.signature.dropLast(1) + "0")))
    }

    @Test
    fun normalizePublicKeyHexRejectsWrongLength() {
        assertEquals("ab".repeat(32), TombstoneSigning.normalizePublicKeyHex("AB".repeat(32)))
        assertEquals(null, TombstoneSigning.normalizePublicKeyHex("abcd"))
        assertEquals(null, TombstoneSigning.normalizePublicKeyHex("zz".repeat(32)))
    }
}
