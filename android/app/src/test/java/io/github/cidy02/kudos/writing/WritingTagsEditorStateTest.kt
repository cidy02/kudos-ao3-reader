package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class WritingTagsEditorStateTest {
    @Test fun returnCommaPasteSuggestionRemovalAndReorderKeepEveryOtherFieldForAllThreeForms() = runTest {
        for (id in listOf(null, 995001L, 995006L)) for (kind in WritingTagKind.entries) {
            val setup = workFormSetup()
            val form = setup.model(id).also { it.load() }
            val client = WritingTagTestClient()
            val recorded = mutableListOf<String>()
            val editor = WritingTagsEditorState(kind, AO3TagAutocompleteRepository(client), this,
                { kind.values(form.state.value.form!!) }, { form.writingTags(kind, it) }, { recorded.add(it) })
            val original = form.state.value.form!!
            val field = kind.formField()
            var expected = kind.values(original)
            fun check(old: AO3WorkForm = original) {
                assertEquals(expected, kind.values(form.state.value.form!!))
                assertDelta(old, form.state.value.form!!, mapOf(field to listOf(expected.joinToString(", "))))
            }
            // Return trims the outside, preserves the inside and appends.
            editor.type("\u0085\u00a0  First  星 \u200b\n")
            editor.add()
            expected = expected + "First  星"; check()
            assertEquals("", editor.state.value.term)
            // No comma listener, no paste splitting. Nothing changes until Return.
            val beforeComma = form.state.value.form!!
            editor.type("one, two,")
            assertEquals(beforeComma, form.state.value.form)
            editor.add(); expected = expected + "one, two,"; check()
            editor.type("  pasted A, pasted B  ")
            assertEquals(expected, kind.values(form.state.value.form!!))
            editor.add(); expected = expected + "pasted A, pasted B"; check()
            // A suggestion's name, not its id, is added through the same path.
            editor.type("demo")
            advanceTimeBy(300); runCurrent()
            assertEquals(listOf("Demo First", "Demo Second", "Demo Third"), editor.suggestions())
            editor.add(editor.suggestions()[1]); expected = expected + "Demo Second"; check()
            assertEquals("Demo Second", recorded.last())
            // Exact duplicates keep the field; case variants are separate chosen chips.
            editor.type("  Demo Second  "); editor.add()
            check(); assertEquals("  Demo Second  ", editor.state.value.term)
            assertEquals(4, recorded.size)
            editor.type("demo second"); editor.add()
            expected = expected + "demo second"; check()
            assertTrue(excludesWritingSuggestion(" DEMO SECOND ", expected))
            editor.type("\n\u0085 "); editor.add(); check()
            assertEquals("\n\u0085 ", editor.state.value.term)
            editor.type("")
            editor.remove("First  星"); expected = expected.filterNot { it == "First  星" }; check()
            val moving = expected.first()
            editor.move(moving, expected.last())
            expected = expected.drop(1) + moving; check()
            editor.step(moving, later = false)
            expected = expected.toMutableList().apply {
                val last = lastIndex; val prior = this[last - 1]; this[last - 1] = moving; this[last] = prior
            }; check()
            editor.step(moving, later = true); expected = expected.filterNot { it == moving } + moving; check()
            // iOS has no chosen count/name length guard; large values remain in the payload.
            val long = "星".repeat(160)
            editor.add(long); expected = expected + long; check()
            repeat(80) { index -> editor.add("many-$index"); expected = expected + "many-$index"; check() }
            expected.toList().forEach { editor.remove(it) }; expected = emptyList(); check()
            assertEquals(1, setup.client.gets.size)
            assertEquals(0, setup.client.posts); assertEquals(0, client.posts)
            editor.close()
            val closed = form.state.value.form
            editor.type("late"); editor.add("late"); editor.remove("anything"); editor.move("a", "b"); editor.step("a", true)
            assertEquals(closed, form.state.value.form)
        }
    }

    @Test fun noOpeningReadOneReadAfter300msAndNoReadForAReplacedTerm() = runTest {
        for (kind in WritingTagKind.entries) {
            val client = WritingTagTestClient()
            var values = emptyList<String>()
            val editor = WritingTagsEditorState(kind, AO3TagAutocompleteRepository(client), this, { values }, { values = it })
            advanceTimeBy(1000); runCurrent()
            assertTrue(client.gets.isEmpty())
            editor.type("replaced")
            advanceTimeBy(299); runCurrent(); assertTrue(client.gets.isEmpty())
            editor.type(" demo ")
            advanceTimeBy(299); runCurrent(); assertTrue(client.gets.isEmpty())
            advanceTimeBy(1); runCurrent(); assertEquals(1, client.gets.size)
            val url = client.gets.single().toHttpUrl()
            assertEquals("/autocomplete/${kind.endpoint}", url.encodedPath)
            assertEquals("demo", url.queryParameter("term"))
            assertEquals("https", url.scheme); assertEquals("archiveofourown.org", url.host)
            // Successes/empty responses are cached by trimmed lowercase term.
            editor.type("Demo"); runCurrent(); assertEquals(1, client.gets.size)
            editor.type("none"); advanceTimeBy(300); runCurrent()
            assertEquals(2, client.gets.size); assertEquals("none", editor.typedTerm()); assertTrue(editor.suggestions().isEmpty())
            editor.type("demo"); runCurrent(); assertEquals(2, client.gets.size)
            editor.type("NONE"); runCurrent(); assertEquals(2, client.gets.size)
            editor.type("x"); advanceTimeBy(300); runCurrent() // iOS asks on a single letter.
            assertEquals(3, client.gets.size)
            editor.type(" \n"); advanceTimeBy(300); runCurrent(); assertEquals(3, client.gets.size)
            assertNull(editor.typedTerm()); assertTrue(editor.suggestions().isEmpty())
            editor.type("never read"); editor.close(); advanceTimeBy(1000); runCurrent()
            assertEquals(3, client.gets.size); assertEquals(0, client.posts)
        }
    }

    @Test fun failedReadLeavesTypingAndAddingPossibleAndNoSuccessClaims() = runTest {
        val client = WritingTagTestClient()
        var values = emptyList<String>()
        val editor = WritingTagsEditorState(WritingTagKind.Freeform, AO3TagAutocompleteRepository(client), this, { values }, { values = it })
        editor.type("fail"); advanceTimeBy(300); runCurrent()
        assertEquals(WritingTagFailure, editor.state.value.error)
        assertEquals("fail", editor.typedTerm()); assertTrue(editor.suggestions().isEmpty())
        editor.add(); assertEquals(listOf("fail"), values); assertNull(editor.state.value.error)
        editor.type("demo"); advanceTimeBy(300); runCurrent()
        assertEquals(3, editor.suggestions().size)
        editor.type("Demo First")
        assertNull(editor.typedTerm()) // Stale prefix suggestions remain during the new wait.
        editor.add("Demo First")
        editor.type("demo"); runCurrent()
        assertEquals(listOf("Demo Second", "Demo Third"), editor.suggestions())
        editor.type("none"); advanceTimeBy(300); runCurrent()
        assertEquals("none", editor.typedTerm())
        editor.close(); assertEquals(0, client.posts)
    }

    @Test fun termChangeAndClosingCancelTheInFlightReadAndRejectLateAnswers() = runTest {
        for (closing in listOf(false, true)) {
            val client = WritingTagTestClient()
            val started = CompletableDeferred<Unit>()
            var cancelled = false
            client.beforeResponse = {
                started.complete(Unit)
                try { awaitCancellation() } catch (error: CancellationException) { cancelled = true; throw error }
            }
            val editor = WritingTagsEditorState(WritingTagKind.Fandom, AO3TagAutocompleteRepository(client), this, { emptyList() }, {})
            editor.type("held"); advanceTimeBy(300); runCurrent(); assertTrue(started.isCompleted)
            if (closing) editor.close() else editor.type("")
            runCurrent(); assertTrue(cancelled)
            assertTrue(editor.state.value.names.isEmpty()); assertNull(editor.state.value.error)
            editor.close(); assertEquals(1, client.gets.size)
        }
    }

    @Test fun exactRemovalAndIosReorderEdges() = runTest {
        var values = listOf("A", "B", "C", "A")
        val editor = WritingTagsEditorState(WritingTagKind.Fandom, null, this, { values }, { values = it })
        editor.remove("A"); assertEquals(listOf("B", "C"), values)
        editor.move("C", "B"); assertEquals(listOf("C", "B"), values)
        editor.move("C", "B"); assertEquals(listOf("B", "C"), values)
        editor.step("B", false); editor.step("C", true); editor.move("missing", "B")
        assertEquals(listOf("B", "C"), values)
        editor.move("C", "missing"); assertEquals(listOf("B", "C"), values)
        editor.close()
    }

    @Test fun foundationTrimAndEncoderPreserveNonWhitespaceControlsAndInteriorWhitespace() {
        val raw = "\u001cNAME\u001f"
        assertEquals(raw, trimWritingTag(raw))
        assertEquals("a \n b", trimWritingTag("\u3000 a \n b \u0085"))
        assertEquals("$raw, a \n b", joinWritingTags(listOf(raw, " a \n b ", "\u0085")))
    }
}

internal fun WritingTagKind.formField(): String = when (this) {
    WritingTagKind.Fandom -> AO3WorkFormField.fandoms
    WritingTagKind.Relationship -> AO3WorkFormField.relationships
    WritingTagKind.Character -> AO3WorkFormField.characters
    WritingTagKind.Freeform -> AO3WorkFormField.additionalTags
}

/** In-memory only. POST throws so any accidental send fails the test. */
internal class WritingTagTestClient : AO3Client, AO3FormPostClient {
    val gets = mutableListOf<String>()
    var posts = 0
    var beforeResponse: suspend () -> Unit = {}
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets.add(url)
        beforeResponse()
        return when (url.toHttpUrl().queryParameter("term")?.lowercase()) {
            "fail" -> AO3Result.Failure(AO3Error.Forbidden)
            "demo" -> AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(),
                """[{"id":"ignored-id","name":"Demo First"},{"id":"2","name":"Demo Second"},{"id":"3","name":"Demo Third"}]"""))
            else -> AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), "[]"))
        }
    }
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts++; error("The work tags picker must never send anything")
    }
}
