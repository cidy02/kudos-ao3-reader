package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipantRole
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipantsParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipantsUrls
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import java.io.File
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test

class DemoCollectionMaintainersTest {
    @Test fun localParticipantsInviteRefusalLeaveAndLastOwnerNeverReachASocket() {
        val client = client()
        fun read(slug: String) = send(client, AO3CollectionParticipantsUrls.page(slug))
        val parser = AO3CollectionParticipantsParser()
        val original = read("winter_exchange")
        assertEquals(200, original.first)
        val people = parser.parse(original.second)
        assertEquals(2, people.count { it.role == AO3CollectionParticipantRole.Owner.title })
        assertEquals(2, people.count { it.role == AO3CollectionParticipantRole.Moderator.title })
        assertEquals(1, people.count { it.role == AO3CollectionParticipantRole.Invited.title })
        assertEquals(listOf("mapfold", "ashletter"), people.filter { it.isMembershipRequest }.map { it.pseud })
        assertEquals(people.size, people.map { it.pseud }.distinct().size)
        val token = AO3WriteFormParser().parseAuthenticityToken(original.second, metaOnly = true)!!
        assertEquals(422, send(client, AO3CollectionParticipantsUrls.add("winter_exchange"),
            listOf("authenticity_token" to "wrong", "participants_to_invite" to "lanternkeeper")).first)
        assertEquals(422, send(client, AO3CollectionParticipantsUrls.add("winter_exchange"),
            listOf("authenticity_token" to token, "participants_to_invite" to "lanternkeeper", "role" to "Owner")).first)
        val refused = send(client, AO3CollectionParticipantsUrls.add("winter_exchange"),
            listOf("authenticity_token" to token, "participants_to_invite" to "unknown_username"))
        assertEquals(422, refused.first)
        assertEquals("We couldn't find an account named unknown_username.", AO3WriteFormParser().writeErrorMessage(refused.second))
        assertEquals(people, parser.parse(read("winter_exchange").second))
        assertEquals(200, send(client, AO3CollectionParticipantsUrls.add("winter_exchange"),
            listOf("authenticity_token" to token, "participants_to_invite" to "lanternkeeper")).first)
        val invited = parser.parse(read("winter_exchange").second)
        assertEquals(8, invited.size)
        assertEquals(AO3CollectionParticipantRole.Invited.title, invited.last().role)
        assertEquals("lanternkeeper", invited.last().pseud)
        assertEquals(200, send(client, AO3CollectionParticipantsUrls.participant("winter_exchange", 105),
            listOf("_method" to "patch", "authenticity_token" to token, "collection_participant[participant_role]" to "Member")).first)
        assertEquals(200, send(client, AO3CollectionParticipantsUrls.participant("winter_exchange", 106),
            listOf("_method" to "delete", "authenticity_token" to token)).first)
        val decided = parser.parse(read("winter_exchange").second)
        assertEquals("Member", decided.first { it.id == 105 }.role)
        assertFalse(decided.any { it.id == 106 })
        assertTrue(decided.any { it.pseud == "lanternkeeper" && it.role == "Invited" })
        val show = send(client, AO3CollectionFormUrls.show("winter_exchange"))
        val showToken = AO3WriteFormParser().parseAuthenticityToken(show.second, metaOnly = true)!!
        assertEquals(422, send(client, AO3CollectionParticipantsUrls.participant("winter_exchange", 101),
            listOf("_method" to "delete", "authenticity_token" to token)).first)
        assertEquals(200, send(client, AO3CollectionParticipantsUrls.participant("winter_exchange", 101),
            listOf("_method" to "delete", "authenticity_token" to showToken)).first)
        val afterLeave = parser.parse(read("winter_exchange").second)
        assertFalse(afterLeave.any { it.id == 101 || it.id == 106 || it.isMembershipRequest })
        assertEquals(3, afterLeave.count { it.isMaintainer })
        assertEquals("Member", afterLeave.first { it.id == 105 }.role)
        assertTrue(afterLeave.any { it.pseud == "lanternkeeper" && it.role == "Invited" })
        val onlyOwner = parser.parse(read("rare_pairs").second)
        assertEquals(listOf("AO3_Reader"), onlyOwner.map { it.pseud })
        assertEquals(200, send(client, "${AO3CollectionFormUrls.show("rare_pairs")}/profile").first)
        assertEquals(422, send(client, AO3CollectionParticipantsUrls.participant("rare_pairs", 101),
            listOf("_method" to "delete", "authenticity_token" to showToken)).first)
        assertEquals(onlyOwner, parser.parse(read("rare_pairs").second))
    }

    @Test fun missingAssetsAndUnknownParticipantWritesAreTerminalFailures() {
        val missing = client(FixtureSource { null })
        for (slug in listOf("winter_exchange", "rare_pairs")) {
            assertEquals(404, send(missing, AO3CollectionParticipantsUrls.page(slug)).first)
            assertEquals(404, send(missing, AO3CollectionFormUrls.show(slug)).first)
            assertEquals(404, send(missing, AO3CollectionParticipantsUrls.add(slug), emptyList()).first)
            assertEquals(404, send(missing, AO3CollectionParticipantsUrls.participant(slug, 101), emptyList()).first)
        }
        assertEquals(422, send(client(), AO3CollectionParticipantsUrls.participant("winter_exchange", 999), emptyList()).first)
    }

    private fun client(source: FixtureSource = FixtureSource { name ->
        listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
            .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes()
    }) = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = { source }))
        .addInterceptor { throw AssertionError("Maintainers demo attempted a socket request") }.build()

    private fun send(client: OkHttpClient, url: String, fields: List<Pair<String, String>>? = null): Pair<Int, String> {
        val request = Request.Builder().url(url).apply {
            if (fields != null) post(FormBody.Builder().apply { fields.forEach { (key, value) -> add(key, value) } }.build())
        }.build()
        return client.newCall(request).execute().use { it.code to it.body.string() }
    }
}
