package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.*
import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AO3ChallengeSettingsEditTest {
    @Test fun openingCountsBothKindsInSwiftOrderAndRemembersFailedOptionalReads() = runTest {
        for (meme in listOf(false, true)) {
            val (auth, client, repository) = challengeEditSetup(meme)
            val model = AO3ChallengeSettingsEditState(client.slug, true, repository, client.writer(auth))
            model.load(); model.load()
            assertEquals(client.openingReads, client.gets)
            assertEquals(if (meme) 5 else 4, client.gets.size)
            assertTrue(client.headers.all { it["Cookie"].orEmpty().isNotBlank() })
            assertEquals(0, client.sent.size)
            assertEquals(if (meme) 0 else null, model.state.value.data!!.signUpTotal)
            assertTrue(model.state.value.data!!.tagSets.isNotEmpty())
            assertNotNull(model.state.value.data!!.collection)
            assertFalse(client.gets.any { it.contains("assignments") || it.contains("page=") })
        }
        val (auth, client, repository) = challengeEditSetup()
        client.replies[client.signups] = AO3Result.Failure(AO3Error.Forbidden)
        client.replies[client.profile] = AO3Result.Failure(AO3Error.Forbidden)
        client.replies[client.collectionEdit] = AO3Result.Failure(AO3Error.Forbidden)
        val model = AO3ChallengeSettingsEditState(client.slug, true, repository, client.writer(auth))
        model.load(); model.load()
        assertEquals(client.openingReads, client.gets)
        assertNotNull(model.state.value.data?.form)
        assertNull(model.state.value.data?.collection)
        assertNull(model.state.value.data?.signUpTotal)
        assertEquals(emptyList<AO3ChallengeTagSet>(), model.state.value.data!!.tagSets)
    }

    @Test fun requiredFailureAndPermissionRefusalStopReadsAndSignedOutOrNonOwnerReadNothing() = runTest {
        for (signedIn in listOf(false, true)) for (owner in listOf(false, true)) {
            val (auth, client, repository) = challengeEditSetup(signedIn = signedIn)
            client.replies[client.edit] = AO3Result.Failure(AO3Error.Forbidden)
            val model = AO3ChallengeSettingsEditState(client.slug, owner, repository, client.writer(auth))
            model.load(); model.load(); model.load(refresh = true)
            assertEquals(if (signedIn && owner) listOf(client.edit) else emptyList<String>(), client.gets)
            assertFalse(model.state.value.loading); assertTrue(model.state.value.terminal)
            assertEquals(0, client.sent.size)
        }
    }

    @Test fun untouchedBodiesEqualBrowserSubmissionFieldForFieldForBothKindsIncludingUnknowns() {
        for (kind in AO3ChallengeKind.entries) {
            val (html, form) = fixtureForm(kind)
            assertEquals(browserSubmission(html, form.token), form.parameters())
            assertTrue(form.parameters().contains(form.field("unmodeled_caption") to "  Keep this spacing  "))
            assertTrue(form.parameters().contains(form.field("unmodeled_notes") to "An original harbor note.\nSecond line."))
            assertEquals(listOf("71", "72"), form.parameters().filter { it.first == "${form.kind.fieldPrefix}[unmodeled_ids][]" }.map { it.second })
            assertEquals(listOf("put"), form.parameters().filter { it.first == "_method" }.map { it.second })
            assertEquals(listOf("Update Challenge"), form.parameters().filter { it.first == "commit" }.map { it.second })
            assertFalse(form.parameters().any { (key, _) -> form.controls.any { it.name == key && it.disabled } })
            assertTrue(form.validated().isValid)
            // These are iOS's same prefix/date/limits; Android adds no absent modeled field.
            val body = form.parameters().toMap()
            assertEquals("1", body[form.field("requests_num_required")])
            assertEquals("3", body[form.field("requests_num_allowed")])
            assertEquals(form.value("signups_open_at_string"), body[form.field("signups_open_at_string")])
            assertEquals("UTC", body[form.field("time_zone")])
            assertFalse(body.containsKey(form.field("request_description_label"))) // absent: Swift invents an empty value
        }
    }

    @Test fun eachTextSwitchNumberDateAndChoiceChangesOnlyThatControlAndAcceptedFormKeepsItsBody() {
        for (kind in AO3ChallengeKind.entries) {
            val (_, form) = fixtureForm(kind)
            val updates = listOf("signup_instructions_general" to "An edited original instruction.",
                "request_restriction_attributes][url_allowed" to "0", "requests_num_allowed" to "4",
                "signups_open_at_string" to form.value("signups_open_at_string").replace("01 00", "02 00")) +
                if (kind == AO3ChallengeKind.GiftExchange) listOf("potential_match_settings_attributes][num_required_fandoms" to "-1")
                else listOf("anonymous" to "0")
            for ((key, value) in updates) {
                val name = form.field(key)
                val edited = form.changed(name, value)
                assertNotEquals(form.parameters(), edited.parameters())
                assertEquals(form.parameters().filterNot { it.first == name }, edited.parameters().filterNot { it.first == name })
                assertEquals(edited.parameters(), edited.accepted().parameters())
                assertTrue(edited.accepted().changes.isEmpty())
            }
        }
    }

    @Test fun absentDisabledUnreadableZoneAndUnreadableDateCannotBeChangedAndPastRevealsFollowSwiftCode() {
        val (_, meme) = fixtureForm(AO3ChallengeKind.PromptMeme)
        for (field in listOf("request_restriction_attributes][fandom_num_required", "request_restriction_attributes][fandom_num_allowed",
            "request_restriction_attributes][allow_any_fandom", "request_restriction_attributes][optional_tags_allowed", "missing"))
            assertEquals(meme, meme.changed(meme.field(field), "9"))
        val (html, gift) = fixtureForm(AO3ChallengeKind.GiftExchange)
        val noZone = AO3ChallengeSettingsFormParser().parse(html.replace("value=\"UTC\" selected", "value=\"\" selected"), gift.slug, gift.kind)
        assertFalse(noZone.scheduleIsEditable)
        for (date in challengeDateKeys) {
            val name = noZone.dateField(date)!!
            assertEquals(noZone, noZone.changed(name, "2030-01-01 00:00:00"))
        }
        assertEquals(browserSubmission(html.replace("value=\"UTC\" selected", "value=\"\" selected"), gift.token), noZone.parameters())
        val unreadable = AO3ChallengeSettingsFormParser().parse(html.replace("2026-01-01 00:00:00", "unreadable AO3 date"), gift.slug, gift.kind)
        assertEquals(unreadable, unreadable.changed(unreadable.dateField("signups_open_at")!!, "2030-01-01 00:00:00"))
        // Swift has no past-date guard despite its footnote. An earlier reveal still after due is accepted.
        assertTrue(gift.changed(gift.dateField("works_reveal_at")!!, "2026-03-20 00:00:00").validated().isValid)
        val wrongChoice = gift.field("potential_match_settings_attributes][num_required_fandoms")
        assertEquals(gift, gift.changed(wrongChoice, "999"))
        // A radio group is several controls of one name: a change is refused, and the body stays the browser's.
        val radios = html.replace("</form>", "<input type=\"radio\" name=\"gift_exchange[mode]\" value=\"a\" checked>" +
            "<input type=\"radio\" name=\"gift_exchange[mode]\" value=\"b\"></form>")
        val withRadios = AO3ChallengeSettingsFormParser().parse(radios, gift.slug, gift.kind)
        assertEquals(withRadios, withRadios.changed(withRadios.field("mode"), "b"))
        assertEquals(browserSubmission(radios, gift.token), withRadios.parameters())
    }

    @Test fun pickerDatesKeepServedPrecisionAndMissingAndUnknownControlsStayAbsent() {
        val date = java.time.LocalDateTime.of(2030, 2, 3, 4, 5, 6)
        for ((source, expected) in listOf("2026-01-01 00:00:00" to "2030-02-03 04:05:06",
            "2026-01-01 00:00" to "2030-02-03 04:05", "2026-01-01" to "2030-02-03",
            "2026-01-01T00:00:00Z" to "2030-02-03T04:05:06Z", "" to "2030-02-03 04:05:06"))
            assertEquals(expected, challengeEditedDateText(source, date))
        val (html, form) = fixtureForm(AO3ChallengeKind.GiftExchange)
        val extra = html.replace("</form>", "<input name='gift_exchange[requests_num_allowed]' value='8'></form>")
        val repeated = AO3ChallengeSettingsFormParser().parse(extra, form.slug, form.kind)
        assertEquals(listOf("3", "9"), repeated.changed(repeated.field("requests_num_allowed"), "9")
            .parameters().filter { it.first == repeated.field("requests_num_allowed") }.map { it.second })
        val missing = html.replace("<input name=\"gift_exchange[works_reveal_at_string]\" value=\"2026-04-01 00:00:00\">", "")
        val omitted = AO3ChallengeSettingsFormParser().parse(missing, form.slug, form.kind)
        assertNull(omitted.dateField("works_reveal_at"))
        assertEquals(omitted, omitted.changed(omitted.field("works_reveal_at_string"), "2030-01-01 00:00:00"))
    }

    @Test fun validationUsesEverySwiftSentenceAndDateOrderWithoutPosting() {
        val (_, gift) = fixtureForm(AO3ChallengeKind.GiftExchange)
        val cases = listOf("requests_num_required" to ("0" to "At least one request is required."),
            "requests_num_allowed" to ("0" to "Allowed requests cannot be fewer than required requests."),
            "offers_num_required" to ("0" to "At least one offer is required."),
            "offers_num_allowed" to ("0" to "Allowed offers cannot be fewer than required offers."),
            "signups_close_at_string" to ("2025-01-01 00:00:00" to "This date is before the previous deadline."))
        for ((key, valueAndError) in cases) assertEquals(valueAndError.second,
            gift.changed(gift.field(key), valueAndError.first).validated().fieldErrors[gift.field(key)])
    }

    @Test fun saveFreshTokenOnePostAndEveryVerdictKeepsTypedTextUnlessConfirmed() = runTest {
        for (meme in listOf(false, true)) for ((status, body, message) in listOf(
            Triple(200, "<div class='flash notice'>Challenge saved.</div>", "Challenge saved."),
            Triple(200, "<p>Successfully updated</p>", "Challenge was successfully updated."),
            Triple(302, "", "Challenge updated."),
            Triple(422, "<div class='flash error'>AO3's exact refusal.</div>", "AO3's exact refusal."),
            Triple(200, "<p>Unconfirmed reply</p>", AO3CollectionFields.UNCONFIRMED),
            Triple(302, "<div class='flash notice'>Saved</div><div class='flash error'>Error wins.</div>", "Error wins.")
        )) {
            val (auth, client, repository) = challengeEditSetup(meme)
            val model = AO3ChallengeSettingsEditState(client.slug, true, repository, client.writer(auth))
            model.load()
            val key = model.state.value.data!!.form.field("signup_instructions_general")
            model.change(key, "Typed text stays")
            val desired = model.state.value.data!!.form
            client.replies[client.edit] = challengeResponse(client.edit, "<meta name='csrf-token' content='fresh+/='>")
            client.postResult = AO3Result.Success(AO3HttpResponse(desired.actionUrl, status, emptyMap(), body))
            val start = client.gets.size
            model.save()
            assertEquals(listOf(client.edit), client.gets.drop(start)); assertEquals(1, client.sent.size)
            assertEquals(desired.copy(token = "fresh+/=").parameters(), client.sent.single().fields)
            assertEquals(desired.actionUrl, client.sent.single().url)
            assertEquals("fresh+/=", client.sent.single().headers["X-CSRF-Token"])
            assertEquals(client.edit, client.sent.single().headers["Referer"])
            assertEquals("Typed text stays", model.state.value.data!!.form[key])
            assertEquals(message, model.state.value.notice ?: model.state.value.data!!.form.generalErrors.single())
            assertFalse(model.state.value.saving)
        }
    }

    @Test fun freshReadFailureMissingMetaSignedOutAndSessionChangedAfterPostHaveNoInventedVerdict() = runTest {
        for (problem in listOf("failed", "missing", "before", "after", "login")) {
            val (auth, client, repository) = challengeEditSetup()
            val model = AO3ChallengeSettingsEditState(client.slug, true, repository, client.writer(auth))
            model.load()
            if (problem == "failed") client.replies[client.edit] = AO3Result.Failure(AO3Error.Forbidden)
            if (problem == "missing") client.replies[client.edit] = challengeResponse(client.edit, "<input name='authenticity_token' value='no-meta'>")
            if (problem == "before") client.afterGet = { if (it == client.edit) auth.logout() }
            if (problem == "after") client.afterPost = { auth.logout() }
            if (problem == "login") { client.postResult = AO3Result.Failure(AO3Error.AuthenticationRequired); client.afterPost = { auth.logout() } }
            model.save()
            assertEquals(if (problem in listOf("after", "login")) 1 else 0, client.sent.size)
            assertFalse(model.state.value.saving)
            val expected = when (problem) {
                "failed" -> AO3Error.Forbidden.moderationMessage()
                "missing" -> "Couldn't prepare the request. Try again, or open the collection on AO3."
                "after" -> AO3CollectionFields.UNCONFIRMED
                "login" -> AO3Error.AuthenticationRequired.moderationMessage()
                else -> null
            }
            assertEquals(expected, model.state.value.data!!.form.generalErrors.firstOrNull())
        }
        val (auth, client, _) = challengeEditSetup(signedIn = false)
        val form = fixtureForm(AO3ChallengeKind.GiftExchange).second
        assertEquals(AO3Result.Failure(AO3Error.Validation("Log in to AO3 first.")), client.writer(auth).saveChallengeSettings(form, auth.generation.value))
        assertTrue(client.gets.isEmpty()); assertTrue(client.sent.isEmpty())
    }

    @Test fun revealConfirmationOnlyForCollectionTrueToFalseAndSecondTapRefreshSendNothingWhileBusy() = runTest {
        val (auth, client, repository) = challengeEditSetup()
        val model = AO3ChallengeSettingsEditState(client.slug, true, repository, client.writer(auth))
        model.load()
        val key = AO3CollectionFields.preference("anonymous")
        model.change(key, "0", collection = true)
        val start = client.gets.size
        model.save()
        assertTrue(model.state.value.confirmReveal); assertEquals(start, client.gets.size); assertTrue(client.sent.isEmpty())
        model.cancelReveal(); assertFalse(model.state.value.confirmReveal)
        model.save(); assertTrue(model.state.value.confirmReveal)
        client.holdPost = true
        val job = async { model.save(revealConfirmed = true) }; runCurrent()
        assertTrue(model.state.value.saving); assertFalse(model.state.value.confirmReveal)
        model.save(revealConfirmed = true); model.load(refresh = true)
        model.change(model.state.value.data!!.form.field("signup_instructions_general"), "Must not change during Save")
        assertEquals(1, client.sent.size)
        client.releasePost.complete(Unit); job.await()
        assertEquals(listOf(client.edit, client.collectionEdit), client.gets.drop(start))
        assertEquals(2, client.sent.size) // Swift's conditional second collection POST
        assertFalse(model.state.value.saving); assertFalse(model.revealsSomething())
        val collection = model.state.value.data!!.collection!!
        assertEquals("0", collection[key])
        assertEquals("patch", client.sent.last().fields.toMap()["_method"])
        assertEquals("demo-collection-edit-token", client.sent.last().fields.toMap()["authenticity_token"])
    }

    @Test fun challengeRefusalSkipsCollectionWriteRefreshKeepsDraftAndDatesDoNotAskToReveal() = runTest {
        val (auth, client, repository) = challengeEditSetup()
        val model = AO3ChallengeSettingsEditState(client.slug, true, repository, client.writer(auth))
        model.load()
        val form = model.state.value.data!!.form
        model.change(form.field("signup_instructions_general"), "Draft before refresh")
        model.change(AO3CollectionFields.preference("closed"), "1", collection = true)
        assertFalse(model.revealsSomething())
        model.load(refresh = true)
        assertEquals("Draft before refresh", model.state.value.data!!.form.value("signup_instructions_general"))
        client.postResult = AO3Result.Success(AO3HttpResponse(form.actionUrl, 422, emptyMap(), "<div class='flash error'>No changes saved.</div>"))
        model.save()
        assertEquals(1, client.sent.size); assertFalse(model.state.value.confirmReveal)
        assertEquals("Draft before refresh", model.state.value.data!!.form.value("signup_instructions_general"))
        assertEquals("1", model.state.value.data!!.collection!![AO3CollectionFields.preference("closed")])
        model.change(form.dateField("works_reveal_at")!!, "2026-03-20 00:00:00")
        assertFalse(model.revealsSomething())
    }
}

internal fun fixtureForm(kind: AO3ChallengeKind): Pair<String, AO3ChallengeSettingsForm> {
    val meme = kind == AO3ChallengeKind.PromptMeme
    val html = challengeFixture(if (meme) "ao3_demo_meme_settings" else "ao3_demo_winter_settings")
    return html to AO3ChallengeSettingsFormParser().parse(html, if (meme) "summer_meme" else "winter_exchange", kind)
}

/** Independent fixture browser oracle; deliberately does not call the app snapshot/serializer. */
private fun browserSubmission(html: String, token: String): List<Pair<String, String>> {
    val form = Jsoup.parse(html).selectFirst("form")!!
    var submitted = false
    return form.select("input, select, textarea, button").flatMap { element ->
        val name = element.attr("name")
        val type = element.attr("type")
        when {
            name.isEmpty() || element.hasAttr("disabled") -> emptyList()
            type == "submit" && submitted -> emptyList()
            type == "submit" -> { submitted = true; listOf(name to element.attr("value")) }
            type in listOf("checkbox", "radio") && !element.hasAttr("checked") -> emptyList()
            type in listOf("checkbox", "radio") -> listOf(name to element.attr("value").ifEmpty { "on" })
            element.tagName() == "select" -> (element.select("option[selected]").ifEmpty { element.select("option").take(1) })
                .filterNot { it.hasAttr("disabled") }.map { name to it.attr("value") }
            element.tagName() == "textarea" -> listOf(name to element.wholeText())
            else -> listOf(name to if (name == "authenticity_token") token else element.attr("value"))
        }
    }
}

internal suspend fun challengeEditSetup(meme: Boolean = false, signedIn: Boolean = true):
    Triple<AO3AuthRepository, ChallengeEditClient, AO3CollectionDetailRepository> {
    val auth = AO3AuthRepository(MemorySessionStore(if (signedIn) testSession() else null), MemoryCookieStore())
    auth.restoreSession()
    val client = ChallengeEditClient(meme)
    return Triple(auth, client, AO3CollectionDetailRepository(client, auth, parseDispatcher = Dispatchers.Unconfined))
}
internal data class ChallengeEditPost(val url: String, val fields: List<Pair<String, String>>, val headers: Map<String, String>)
internal class ChallengeEditClient(val meme: Boolean) : AO3Client, AO3FormPostClient {
    val slug = if (meme) "summer_meme" else "winter_exchange"
    val kind = if (meme) AO3ChallengeKind.PromptMeme else AO3ChallengeKind.GiftExchange
    val edit = ChallengeSettingsDestinations.challengeSettingsEditView(slug, kind)
    val gift = ChallengeSettingsDestinations.challengeSettingsEditView(slug, AO3ChallengeKind.GiftExchange)
    val signups = ChallengeSettingsDestinations.signUpPage(slug)
    val profile = ChallengeSettingsDestinations.profile(slug)
    val collectionEdit = AO3CollectionFormUrls.form(slug)
    val openingReads get() = (if (meme) listOf(gift, edit) else listOf(edit)) + listOf(signups, profile, collectionEdit)
    val gets = mutableListOf<String>()
    val headers = mutableListOf<Map<String, String>>()
    val replies = mutableMapOf<String, AO3Result<AO3HttpResponse>>()
    val sent = mutableListOf<ChallengeEditPost>()
    var afterGet: suspend (String) -> Unit = {}
    var afterPost: suspend () -> Unit = {}
    var holdPost = false
    val releasePost = CompletableDeferred<Unit>()
    var postResult: AO3Result<AO3HttpResponse> = challengeResponse("https://archiveofourown.org", "<div class='flash notice'>Challenge updated.</div>")
    fun writer(auth: AO3AuthRepository) = AO3WriteRepository(DefaultAO3AuthenticatedClient(this, this, auth))
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url; this.headers += headers
        afterGet(url)
        return replies[url] ?: if (meme && url == gift) AO3Result.Failure(AO3Error.NotFound) else challengeResponse(url, when (url) {
            edit -> challengeFixture(if (meme) "ao3_demo_meme_settings" else "ao3_demo_winter_settings")
            signups -> challengeFixture(if (meme) "ao3_demo_meme_signups" else "ao3_demo_winter_signups_1")
            profile -> if (meme) "<dl><dt>Tag set:</dt><dd><a href='/tag_sets/44'>Summer Prompt Tags</a></dd></dl>"
                else challengeFixture("ao3_collection_show")
            collectionEdit -> challengeFixture(if (meme) "ao3_demo_meme_collection_edit" else "ao3_demo_collection_edit")
            else -> error("Unexpected edit read: $url")
        })
    }
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        sent += ChallengeEditPost(url, formFields, headers)
        if (holdPost) releasePost.await()
        afterPost()
        return postResult
    }
}
