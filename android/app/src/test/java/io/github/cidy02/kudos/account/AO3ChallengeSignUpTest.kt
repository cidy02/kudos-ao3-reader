package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.network.ao3.account.*
import io.github.cidy02.kudos.network.ao3.writes.AO3WriteFormParser
import org.jsoup.Jsoup
import org.junit.Assert.*
import org.junit.Test

internal val signUpFixtures = listOf("ao3_demo_signup_winter_new", "ao3_demo_signup_winter_edit", "ao3_demo_signup_summer_new")
internal fun signUpForm(fixture: String = signUpFixtures[0]) = AO3ChallengeSignUpParser().parse(challengeFixture(fixture),
    if (fixture.contains("summer")) "summer_meme" else "winter_exchange")

class AO3ChallengeSignUpTest {
    @Test fun everyFixtureParsesAllFieldsLimitsRawControlsAndOriginalTagSetNames() {
        for (fixture in signUpFixtures) {
            val form = signUpForm(fixture)
            assertEquals(1..3, form.limits?.requests)
            assertEquals(if (fixture.contains("summer")) 0..0 else 1..2, form.limits?.offers)
            assertEquals(!fixture.contains("summer"), form.takesOffers)
            assertEquals("101", form.pseudID)
            assertEquals(if (fixture.endsWith("edit")) listOf("The Lantern Archipelago", "Cloudbound Courier")
                else listOf("The Lantern Archipelago"), form.requests.single().tags[SignUpTagType.Fandom])
            assertEquals("A letter reaches an island after the last boat has left.", form.requests.single().description)
            assertEquals(1..2, form.requestTagLimits?.get(SignUpTagType.Fandom))
            assertEquals(0..4, form.requestTagLimits?.get(SignUpTagType.Character))
            assertTrue(form.validated().isValid)
            assertTrue(form.servedControls.any { it.name == "disabled_future" && it.disabled })
            assertTrue(form.servedControls.any { it.name.isEmpty() })
            assertEquals(2, form.servedControls.count { it.name == "future_repeat" })
            if (fixture.endsWith("edit")) {
                assertEquals(4, form.signUpID)
                assertEquals("put", form.method)
                assertEquals("Lantern post office", form.requests[0].title)
                assertEquals("https://example.org/lantern", form.requests[0].url)
                assertEquals("421", form.carriedParameters().first { it.first.endsWith("[tag_set_attributes][id]") }.second)
            } else assertNull(form.signUpID)
        }
        val known = Jsoup.parse(challengeFixture("ao3_demo_tag_set_42")).select("ul.fandom li").map { it.text() }
        assertTrue(known.contains(signUpForm().requests[0].tags.getValue(SignUpTagType.Fandom).single()))
    }

    @Test fun untouchedFormsCompareToIndependentBrowserOracleWithOnlyThree3bbRules() {
        for (fixture in signUpFixtures) {
            val form = signUpForm(fixture)
            val doc = Jsoup.parse(challengeFixture(fixture))
            val browser = browserPairs(doc)
            val explicit = form.iosParameters()
            val names = explicit.map { it.first }.toSet()
            val checkNames = doc.select("input[type=checkbox]").map { it.attr("name") }.toSet()
            fun normalized(name: String, pairs: List<Pair<String, String>>): List<String> {
                val values = pairs.filter { it.first == name }.map { it.second }
                // Exactly the three rules from 3bb, no missing/empty/textarea/index normalizers.
                return when {
                    name in checkNames && !name.endsWith("[]") -> values.takeLast(1)
                    name.endsWith("_tagnames]") -> values.map { it.split(',').joinToString(",") { tag -> tag.trim() } }
                    doc.select("input[type=submit], button[type=submit]").any { it.attr("name") == name } ->
                        if (values.isEmpty()) emptyList() else listOf("present")
                    else -> values
                }
            }
            for (name in names) assertEquals("$fixture: $name", normalized(name, browser), normalized(name, explicit))
            assertEquals("$fixture: untouched replay", browser.filterNot { it.first in names }, form.carriedParameters())
            assertTrue(names.intersect(form.carriedParameters().map { it.first }.toSet()).isEmpty())
            assertEquals(explicit + form.carriedParameters(), form.parameters())
        }
    }

    @Test fun everyIosFieldKindEncodesInItsExactOrderWithEmptyAndDestroyedPrompts() {
        val form = signUpForm(signUpFixtures[1])
        for (kind in SignUpPromptKind.entries) {
            val old = form.live(kind).single()
            val changed = old.copy(title = "", description = "雪 & <p>Typed</p>\nNext", url = "",
                anonymous = true, destroy = true, any = SignUpTagType.entries.toSet(),
                tags = SignUpTagType.entries.associateWith { listOf("First & 星", "Second") })
            val updated = form.update(changed)
            val base = signUpPromptPrefix(kind, 0)
            assertEquals(listOf("$base[id]" to changed.id.toString(), "$base[title]" to "",
                "$base[description]" to changed.description, "$base[url]" to "", "$base[anonymous]" to "1",
                "$base[any_fandom]" to "1", "$base[any_character]" to "1", "$base[any_relationship]" to "1",
                "$base[any_freeform]" to "1", "$base[_destroy]" to "1") + SignUpTagType.entries.map {
                    "$base[tag_set_attributes][${it.wire}_tagnames]" to "First & 星,Second"
                }, updated.iosParameters().filter { it.first.startsWith("$base[") })
            assertEquals(form.servedControls, updated.servedControls)
        }
        val empty = form.update(form.requests[0].copy(tags = emptyMap(), anonymous = false, any = emptySet()))
        assertEquals("", empty.iosParameters().first { it.first.endsWith("[fandom_tagnames]") }.second)
        val draft = SignUpPrompt(-99, SignUpPromptKind.Request)
        val added = form.copy(requests = form.requests + draft)
        assertFalse(added.iosParameters().any { it.first == "challenge_signup[requests_attributes][1][id]" })
        assertEquals("", added.iosParameters().first { it.first == "challenge_signup[requests_attributes][1][title]" }.second)
        assertEquals("0", added.iosParameters().first { it.first == "challenge_signup[requests_attributes][1][anonymous]" }.second)
        assertFalse(form.copy(pseudID = "", method = null).iosParameters().any { it.first == "_method" || it.first == "challenge_signup[pseud_id]" })
    }

    @Test fun hiddenIdsFollowReindexedPromptsAndSnapshotKeepsUnknownDisabledAndExternalControls() {
        val html = challengeFixture(signUpFixtures[1]).replace("requests_attributes][0]", "requests_attributes][5]")
            .replace("</body>", "<input form='challenge-signup' name='external[]' value='kept'></body>")
        val form = AO3ChallengeSignUpParser().parse(html, "winter_exchange")
        assertEquals(5, form.requests[0].servedIndex)
        assertTrue(form.parameters().contains("challenge_signup[requests_attributes][0][tag_set_attributes][id]" to "421"))
        assertFalse(form.parameters().any { it.first.contains("requests_attributes][5]") })
        assertTrue(form.carriedParameters().contains("external[]" to "kept"))
        assertFalse(form.parameters().any { it.first == "disabled_future" || it.first == "cancel_submit" })
        assertEquals(listOf("Submit"), form.parameters().filter { it.first == "commit" }.map { it.second })
        val sameNameSubmit = AO3ChallengeSignUpParser().parse(html.replace("name=\"cancel_submit\"", "name=\"commit\""), "winter_exchange")
        assertEquals(listOf("Submit"), sameNameSubmit.parameters().filter { it.first == "commit" }.map { it.second })
        assertEquals(listOf("first", "last"), form.parameters().filter { it.first == "future_repeat" }.map { it.second })
        assertEquals(listOf("0", "1"), form.parameters().filter { it.first == "future_flag" }.map { it.second })
    }

    @Test fun allCountValidationsUseIosExactWordsAndDestroyedPromptsDoNotCount() {
        val form = signUpForm()
        for (kind in SignUpPromptKind.entries) {
            val range = if (kind == SignUpPromptKind.Request) form.limits!!.requests else form.limits!!.offers
            fun withPrompts(prompts: List<SignUpPrompt>) = if (kind == SignUpPromptKind.Request) form.copy(requests = prompts) else form.copy(offers = prompts)
            assertEquals("This challenge requires at least ${range.first} ${kind.label.lowercase()}(s).",
                withPrompts(emptyList()).validated().fieldErrors[kind.wire])
            val prompt = form.live(kind).first()
            assertEquals("This challenge allows at most ${range.last} ${kind.label.lowercase()}(s).",
                withPrompts((0..range.last).map { prompt.copy(id = -(it + 1)) }).validated().fieldErrors[kind.wire])
            assertEquals("This challenge requires at least ${range.first} ${kind.label.lowercase()}(s).",
                withPrompts(listOf(prompt.copy(destroy = true))).validated().fieldErrors[kind.wire])
        }
    }

    @Test fun everyTagValidationForBothKindsHasIosWordsOrderAndAnyBehavior() {
        for (kind in SignUpPromptKind.entries) for (type in SignUpTagType.entries) {
            val form = signUpForm()
            val prompt = form.live(kind)[0].copy(tags = emptyMap(), any = emptySet())
            fun checked(tags: Map<SignUpTagType, IntRange>, changed: SignUpPrompt): String? {
                val updated = form.update(changed).let {
                    if (kind == SignUpPromptKind.Request) it.copy(requestTagLimits = tags) else it.copy(offerTagLimits = tags)
                }
                return updated.validated().fieldErrors[prompt.errorKey]
            }
            val prefix = "${kind.label} 1: "
            assertEquals(prefix + "Choose 1 to 2 ${type.plural} (you have 0).", checked(mapOf(type to (1..2)), prompt))
            assertEquals(prefix + "Choose exactly 2 ${type.plural} (you have 0).", checked(mapOf(type to (2..2)), prompt))
            assertEquals(prefix + "This challenge takes no ${type.plural}.", checked(emptyMap(), prompt.copy(tags = mapOf(type to listOf("Tag")))))
            assertEquals(prefix + "Choose ${type.plural} or “Any”, not both.", checked(emptyMap(), prompt.copy(tags = mapOf(type to listOf("Tag")), any = setOf(type))))
            assertNull(checked(mapOf(type to (2..2)), prompt.copy(any = setOf(type))))
        }
        val form = signUpForm()
        assertTrue(form.copy(limits = null, requestTagLimits = null, offerTagLimits = null,
            requests = listOf(form.requests[0].copy(description = "x".repeat(1200), url = "invalid URL", title = ""))).validated().isValid)
        val all = form.update(form.requests[0].copy(tags = SignUpTagType.entries.associateWith { listOf("Tag") }))
            .copy(requestTagLimits = emptyMap()).validated()
        assertEquals("Request 1: This challenge takes no fandoms. This challenge takes no characters. " +
            "This challenge takes no relationships. This challenge takes no additional tags.", all.fieldErrors[form.requests[0].errorKey])
    }

    @Test fun errorsMissingLimitsMinimumDraftsAndUntrustedFormsAreHandled() {
        val parser = AO3ChallengeSignUpParser()
        val raw = challengeFixture(signUpFixtures[0])
        assertThrows(IllegalArgumentException::class.java) { parser.parse(raw.replace("/collections/winter_exchange/signups\"", "https://archiveofourown.org.evil.com/collections/fest/signups\""), "winter_exchange") }
        assertThrows(IllegalStateException::class.java) { parser.parse("<form action='/users/login'></form>", "winter_exchange") }
        val invalid = parser.parse(raw.replace("</main>", challengeFixture("ao3_demo_signup_refused") + "</main>"), "winter_exchange")
        assertEquals(2, invalid.generalErrors.size)
        assertEquals(invalid.generalErrors.first(), AO3WriteFormParser().writeErrorMessage(challengeFixture("ao3_demo_signup_refused")))
        val empty = signUpForm().copy(requests = emptyList(), offers = emptyList()).withMinimumPrompts()
        assertEquals(-1, empty.requests.single().id)
        assertEquals(-2, empty.offers.single().id)
        assertTrue(signUpForm(signUpFixtures[2]).copy(requests = emptyList()).withMinimumPrompts().offers.isEmpty())
        assertEquals(listOf("First", "Second"), splitSignUpTags(" First, , Second "))
    }

    /** Independent fixture DOM oracle; no production snapshot/parser or encoder helpers. */
    private fun browserPairs(doc: org.jsoup.nodes.Document): List<Pair<String, String>> {
        val submitter = doc.select("form input[type=submit], form button[type=submit]").firstOrNull { !it.hasAttr("disabled") }
        return doc.select("form input, form textarea, form select, form button").flatMap { node ->
        val name = node.attr("name")
        val type = node.attr("type")
        when {
            name.isEmpty() || node.hasAttr("disabled") -> emptyList()
            node == submitter -> listOf(name to node.attr("value"))
            node.tagName() == "button" || type in setOf("submit", "reset", "button", "image") -> emptyList()
            type in setOf("checkbox", "radio") && !node.hasAttr("checked") -> emptyList()
            node.tagName() == "textarea" -> listOf(name to node.wholeText())
            node.tagName() == "select" -> {
                val chosen = node.select("option[selected]").toList().ifEmpty { if (node.hasAttr("multiple")) emptyList() else node.select("option").take(1) }
                chosen.filterNot { it.hasAttr("disabled") }.map { name to it.attr("value") }
            }
            else -> listOf(name to node.attr("value"))
        }
    }
    }
}
