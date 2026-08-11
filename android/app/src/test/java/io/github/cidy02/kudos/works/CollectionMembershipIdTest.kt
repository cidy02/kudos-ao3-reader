package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.core.model.canonicalizeCollectionMembershipRecordId
import io.github.cidy02.kudos.core.model.collectionMembershipRecordId
import io.github.cidy02.kudos.core.model.legacyCollectionMembershipRecordId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Cross-platform lock for collection-membership tombstone IDs: Android must
 * produce the same deterministic XOR-UUID as iOS `collectionMembershipID`.
 */
class CollectionMembershipIdTest {
    @Test
    fun xorUuidMatchesIosVerifiedVectorAndIsCommutative() {
        // Verified interop vector (iOS collectionMembershipID / RFC 4122 bytes).
        val a = "12345678-1234-5678-1234-567812345678"
        val b = "87654321-4321-8765-4321-876543218765"
        val expected = "95511559-5115-d11d-5115-d11d5115d11d"

        assertEquals(expected, collectionMembershipRecordId(a, b))
        assertEquals(expected, collectionMembershipRecordId(b, a))
    }

    @Test
    fun canonicalizeAcceptsXorFormAndLegacyColonForm() {
        val a = "12345678-1234-5678-1234-567812345678"
        val b = "87654321-4321-8765-4321-876543218765"
        val xor = collectionMembershipRecordId(a, b)
        val colon = legacyCollectionMembershipRecordId(a, b)

        assertEquals(xor, canonicalizeCollectionMembershipRecordId(xor))
        assertEquals(xor, canonicalizeCollectionMembershipRecordId(colon))
        assertEquals(xor, canonicalizeCollectionMembershipRecordId(xor.uppercase()))
    }

    @Test
    fun canonicalizeRejectsGarbage() {
        assertThrows(IllegalArgumentException::class.java) {
            canonicalizeCollectionMembershipRecordId("not-a-membership-id")
        }
        assertThrows(IllegalArgumentException::class.java) {
            canonicalizeCollectionMembershipRecordId("a:b:c")
        }
    }
}
