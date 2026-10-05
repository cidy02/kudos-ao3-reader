package io.github.cidy02.kudos.network.ao3

import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFields
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormParser
import java.io.File
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.junit.Assert.*
import org.junit.Test

class DemoCollectionFormTest {
    @Test fun newValidationEditAvailabilityAndDeleteAreTerminalLocalAnswers() {
        val client = OkHttpClient.Builder().addInterceptor(DemoNetworkInterceptor(isActive = { true }, fixtures = {
            FixtureSource { name -> listOf("src/debug/assets/fixtures", "app/src/debug/assets/fixtures", "android/app/src/debug/assets/fixtures")
                .map { File(it, "$name.html") }.firstOrNull { it.isFile }?.readBytes() }
        })).addInterceptor { throw AssertionError("Demo attempted a socket request") }.build()
        val parser = AO3CollectionFormParser()
        fun read(path: String): Pair<Int, String> = client.newCall(Request.Builder().url("https://archiveofourown.org$path").build())
            .execute().use { it.code to it.body.string() }
        fun post(path: String, fields: List<Pair<String, String>>): Pair<Int, String> {
            val body = FormBody.Builder().apply { fields.forEach { (key, value) -> add(key, value) } }.build()
            return client.newCall(Request.Builder().url("https://archiveofourown.org$path").post(body).build())
                .execute().use { it.code to it.body.string() }
        }
        assertEquals(404, read("/collections/lantern_archive").first)
        assertEquals(200, read("/collections/taken_name").first)
        val new = parser.parse(read("/collections/new").second, null)
            .changed(AO3CollectionFields.NAME, "lantern_archive").changed(AO3CollectionFields.TITLE, "Lantern Letters")
        val saved = post("/collections", new.parameters())
        assertEquals(200, saved.first)
        assertTrue(saved.second.contains("successfully created"))
        assertEquals(listOf("81", "82"), parser.parse(saved.second, null).ownerIds)
        assertEquals(200, read("/collections/lantern_archive").first)
        assertEquals(404, read("/collections/refused_name").first)
        val refused = post("/collections", new.changed(AO3CollectionFields.NAME, "refused_name").parameters())
        assertEquals(422, refused.first)
        val invalid = parser.parse(refused.second, null)
        assertEquals("Name has already been taken", invalid.fieldErrors[AO3CollectionFields.NAME])
        assertEquals("refused_name", invalid[AO3CollectionFields.NAME])
        assertEquals("Lantern Letters", invalid[AO3CollectionFields.TITLE])
        val edit = parser.parse(read("/collections/winter_exchange/edit").second, "winter_exchange")
        assertTrue(edit.allowsDelete)
        val update = post("/collections/winter_exchange", edit.changed(AO3CollectionFields.TITLE, "Winter Letters").parameters())
        assertEquals(200, update.first)
        assertEquals("Winter Letters", parser.parse(read("/collections/winter_exchange/edit").second, "winter_exchange")[AO3CollectionFields.TITLE])
        assertEquals(422, post("/collections/winter_exchange", listOf("_method" to "delete", "authenticity_token" to "wrong")).first)
        val token = parser.destroyToken(read("/collections/winter_exchange/confirm_delete").second)!!
        assertEquals(200, post("/collections/winter_exchange", listOf("_method" to "delete", "authenticity_token" to token)).first)
        assertEquals(404, read("/collections/winter_exchange/edit").first)
    }
}
