package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.*
import java.io.File
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

class DemoCollectionModerationTest {
    @Test fun browserFallbackParticipantsAndUnknownSubresourcesTerminateInFixtures() {
        val source = FixtureSource { name -> listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
            .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes() }
        val body = DemoNetwork.webFixture("https://archiveofourown.org/collections/winter_exchange/participants".toHttpUrl(), source)!!.decodeToString()
        assertEquals(4, AO3CollectionParticipantsParser().parse(body).count { it.isMaintainer })
        assertNull(DemoNetwork.webFixture("https://example.com/collections/winter_exchange/participants".toHttpUrl(), source))
        assertNull(DemoNetwork.webFixture("https://archiveofourown.org/assets/unknown-script.js".toHttpUrl(), source))
        assertNull(DemoNetwork.webFixture("https://archiveofourown.org/collections/winter_exchange/participants".toHttpUrl(), FixtureSource { null }))
    }

    @Test fun twoQueuePagesRefusalMembershipAndBothRevealsAreTerminalLocalAnswers() {
        val client = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = {
            FixtureSource { name -> listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
                .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes() }
        })).addInterceptor { throw AssertionError("Demo attempted a socket request") }.build()
        fun read(path: String): String = client.newCall(Request.Builder().url("https://archiveofourown.org$path").build())
            .execute().use { assertEquals(200, it.code); it.body.string() }
        fun post(path: String, fields: List<Pair<String, String>>): Pair<Int, String> = client.newCall(Request.Builder()
            .url("https://archiveofourown.org$path").post(FormBody.Builder().apply { fields.forEach { (key, value) -> add(key, value) } }.build()).build())
            .execute().use { it.code to it.body.string() }
        val root = "/collections/winter_exchange"
        val parser = AO3CollectionItemsParser()
        fun queue(page: Int) = parser.parse(read("$root/items" + if (page == 1) "" else "?page=$page"),
            "winter_exchange", AO3CollectionItemTab.Unreviewed, page)
        val first = queue(1)
        assertEquals(2, first.totalPages); assertEquals(listOf(41, 42, 43), first.items.map { it.id })
        assertEquals(listOf(44), queue(2).items.map { it.id })
        assertEquals(200, post("$root/items/update_multiple", AO3CollectionItemDraft(41,
            moderatorApproval = AO3CollectionItemApproval.Approved).parameters(first)).first)
        val refusal = post("$root/items/update_multiple", AO3CollectionItemDraft(42,
            moderatorApproval = AO3CollectionItemApproval.Approved).parameters(first))
        assertEquals(422, refusal.first); assertTrue(refusal.second.contains("AO3 couldn't update that collection item."))
        assertEquals(AO3CollectionItemApproval.Unreviewed, queue(1).items.first { it.id == 42 }.moderatorApproval)
        assertFalse(queue(1).items.any { it.id == 41 })
        val participantParser = AO3CollectionParticipantsParser()
        val originalPeople = participantParser.parse(read("$root/participants"))
        assertEquals(listOf("mapfold", "ashletter"), originalPeople.filter { it.isMembershipRequest }.map { it.pseud })
        assertEquals(2, originalPeople.count { it.isMembershipRequest })
        assertEquals(4, originalPeople.count { it.isMaintainer })
        assertEquals(originalPeople.size, originalPeople.map { it.pseud }.distinct().size)
        assertEquals(422, post("$root/participants/105", listOf("_method" to "patch", "authenticity_token" to "wrong",
            "collection_participant[participant_role]" to "Member")).first)
        assertEquals(200, post("$root/participants/105", listOf("_method" to "patch", "authenticity_token" to "demo-participants-token",
            "collection_participant[participant_role]" to "Member")).first)
        assertEquals(200, post("$root/participants/106", listOf("_method" to "delete", "authenticity_token" to "demo-participants-token")).first)
        val people = participantParser.parse(read("$root/participants"))
        assertTrue(people.none { it.isMembershipRequest }); assertEquals("Member", people.first { it.id == 105 }.role)
        assertTrue(people.none { it.id == 106 }); assertEquals(4, people.count { it.isMaintainer })
        val showParser = AO3CollectionParser()
        val initial = showParser.parseCollectionShow(read(root), "winter_exchange")
        assertTrue(initial.collection.isUnrevealed && initial.collection.isAnonymous)
        val formParser = AO3CollectionFormParser()
        val reveal = formParser.parse(read("$root/edit"), "winter_exchange").changed(AO3CollectionFields.preference("unrevealed"), "0")
        assertEquals(200, post(root, reveal.parameters()).first)
        val revealed = showParser.parseCollectionShow(read(root), "winter_exchange")
        assertFalse(revealed.collection.isUnrevealed); assertTrue(revealed.collection.isAnonymous)
        val unanon = formParser.parse(read("$root/edit"), "winter_exchange").changed(AO3CollectionFields.preference("anonymous"), "0")
        assertEquals(200, post(root, unanon.parameters()).first)
        assertFalse(showParser.parseCollectionShow(read(root), "winter_exchange").collection.isAnonymous)
        assertFalse(formParser.parse(read("$root/edit"), "winter_exchange")[AO3CollectionFields.preference("unrevealed")] == "1")
        // Invite and leave operate on the same server state as the two membership decisions.
        assertEquals(200, post("$root/participants/add", listOf("authenticity_token" to "demo-participants-token",
            "participants_to_invite" to "lanternkeeper")).first)
        val showToken = io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser()
            .parseAuthenticityToken(read(root), metaOnly = true)!!
        assertEquals(200, post("$root/participants/101", listOf("_method" to "delete", "authenticity_token" to showToken)).first)
        val finalPeople = participantParser.parse(read("$root/participants"))
        assertTrue(finalPeople.none { it.isMembershipRequest || it.id == 101 || it.id == 106 })
        assertEquals("Member", finalPeople.first { it.id == 105 }.role)
        assertEquals(3, finalPeople.count { it.isMaintainer })
        assertEquals(listOf("snowink", "lanternkeeper"), finalPeople.filter { it.role == "Invited" }.map { it.pseud })
        val finalShow = showParser.parseCollectionShow(read(root), "winter_exchange")
        assertFalse(finalShow.collection.isUnrevealed || finalShow.collection.isAnonymous)
    }
}
