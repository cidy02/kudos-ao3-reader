package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemApproval
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemDraft
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemTab
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsUrls
import java.io.File
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test

class DemoUserCollectionItemsTest {
    @Test fun accountFiltersPagesCreatorDecisionsAndRefusalsAreTerminalLocalAnswers() {
        val client = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = {
            FixtureSource { name -> listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
                .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes() }
        })).addInterceptor { throw AssertionError("Demo attempted a socket request") }.build()
        val parser = AO3CollectionItemsParser()
        fun read(tab: AO3CollectionItemTab = AO3CollectionItemTab.Invited, page: Int = 1) =
            client.newCall(Request.Builder().url(AO3CollectionItemsUrls.userPage("AO3_Reader", tab, page)!!).build())
                .execute().use { response ->
                    assertEquals(200, response.code)
                    parser.parseUser(response.body.string(), "AO3_Reader", tab, page)
                }
        fun post(fields: List<Pair<String, String>>): Pair<Int, String> {
            val body = FormBody.Builder().apply { fields.forEach { (key, value) -> add(key, value) } }.build()
            return client.newCall(Request.Builder().url(AO3CollectionItemsUrls.userUpdate("AO3_Reader")!!).post(body).build())
                .execute().use { it.code to it.body.string() }
        }
        val page = read()
        assertEquals(listOf(61, 62, 63), page.items.map { it.id })
        assertEquals(2, page.totalPages)
        assertEquals(setOf("Winter Exchange 2026", "Summer Prompt Meme"), page.items.map { it.collectionTitle }.toSet())
        assertEquals(listOf(67), read(page = 2).items.map { it.id })
        assertEquals(listOf(66), read(AO3CollectionItemTab.Unreviewed).items.map { it.id })
        assertEquals(listOf(65), read(AO3CollectionItemTab.Rejected).items.map { it.id })
        assertEquals(listOf(64), read(AO3CollectionItemTab.Approved).items.map { it.id })
        val approved = AO3CollectionItemDraft(61, creatorApproval = AO3CollectionItemApproval.Approved).parameters(page)
        assertEquals(422, post(approved.map { if (it.first == "authenticity_token") it.first to "wrong" else it }).first)
        assertEquals(422, post(AO3CollectionItemDraft(61, moderatorApproval = AO3CollectionItemApproval.Rejected).parameters(page)).first)
        assertEquals(422, post(AO3CollectionItemDraft(61, anonymous = false).parameters(page)).first)
        assertEquals(200, post(approved).first)
        assertFalse(read().items.any { it.id == 61 })
        assertEquals(listOf(61, 64), read(AO3CollectionItemTab.Approved).items.map { it.id })
        val refused = post(AO3CollectionItemDraft(62, creatorApproval = AO3CollectionItemApproval.Approved).parameters(page))
        assertEquals(422, refused.first)
        assertTrue(refused.second.contains("AO3 couldn't update that collection item."))
        assertEquals(AO3CollectionItemApproval.Unreviewed, read().items.first { it.id == 62 }.creatorApproval)
        assertEquals(200, post(AO3CollectionItemDraft(63, remove = true).parameters(page)).first)
        assertFalse(read().items.any { it.id == 63 })
        assertEquals(422, post(AO3CollectionItemDraft(67, remove = true).parameters(page)).first)
    }

    @Test fun missingAccountFixtureCannotFallThroughToNetwork() {
        val client = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = {
            FixtureSource { null }
        })).addInterceptor { throw AssertionError("Missing fixture attempted a socket request") }.build()
        client.newCall(Request.Builder().url(AO3CollectionItemsUrls.userPage("AO3_Reader", AO3CollectionItemTab.Invited, 1)!!).build())
            .execute().use { assertEquals(404, it.code) }
        client.newCall(Request.Builder().url(AO3CollectionItemsUrls.userUpdate("AO3_Reader")!!).post(FormBody.Builder().build()).build())
            .execute().use { assertEquals(404, it.code) }
    }
}
