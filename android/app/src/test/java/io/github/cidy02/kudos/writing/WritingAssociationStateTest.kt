package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.account.AO3AccountUrls
import io.github.cidy02.kudos.network.ao3.search.AO3TagAutocompleteRepository
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.*
import okhttp3.HttpUrl.Companion.toHttpUrl
import org.junit.Assert.*
import org.junit.Test

@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class WritingAssociationStateTest {
    private val forms = listOf(null, 995001L, 995006L)
    private val seriesFields = setOf(AO3WorkFormField.seriesID, AO3WorkFormField.seriesTitle)

    @Test fun pickingASeriesPostsOnlyThatSeriesAndWhitespaceOnlySeriesTitleIsNotPosted() = runTest {
        for (id in forms) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            var old = model.state.value.form!!
            model.selectSeries(88)
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.seriesID to listOf("88"), AO3WorkFormField.seriesTitle to listOf("")))
            assertEquals(listOf(88L), model.state.value.form!!.series.filter { it.isSelected }.map { it.seriesID })
            old = model.state.value.form!!
            model.selectSeries(88)
            assertDelta(old, model.state.value.form!!, seriesFields.associateWith { listOf("") })
            old = model.state.value.form!!
            model.newSeries("\u0085  Water 星 \u200b")
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.seriesID to listOf(""), AO3WorkFormField.seriesTitle to listOf("Water 星")))
            old = model.state.value.form!!
            model.selectSeries(88)
            assertEquals("", model.state.value.form!!.newSeriesTitle)
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.seriesID to listOf("88"), AO3WorkFormField.seriesTitle to listOf("")))
            old = model.state.value.form!!
            model.newSeries(" \u200b\n ")
            assertEquals(listOf(88L), model.state.value.form!!.series.filter { it.isSelected }.map { it.seriesID })
            assertDelta(old, model.state.value.form!!, emptyMap())
            model.newSeries("New")
            assertTrue(model.state.value.form!!.series.none { it.isSelected })
            old = model.state.value.form!!
            model.newSeries("   ")
            assertDelta(old, model.state.value.form!!, seriesFields.associateWith { listOf("") })
            old = model.state.value.form!!
            model.selectSeries(9999)
            assertEquals(old, model.state.value.form)
            if (id == 995006L) {
                model.selectSeries(77) // Current membership is read-only, cannot remove or select it.
                assertEquals(old, model.state.value.form)
                assertEquals("Lantern Voyages", old.seriesValue())
            }
            assertEquals(old.currentSeries, model.state.value.form!!.currentSeries)
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
    }

    @Test fun collectionsOfferAdditionIsUntickedThenSelectionAndClearingDriveEverySubmit() = runTest {
        for (id in forms) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            var old = model.state.value.form!!
            val offer = AO3CollectionOffer("slowburn_2026", "Slow Burn Exchange 2026", AO3CollectionAccess(isDescribed = false), true)
            model.addCollection(offer)
            assertFalse(model.state.value.form!!.collections.last().isSelected)
            assertDelta(old, model.state.value.form!!, emptyMap())
            old = model.state.value.form!!
            model.addCollection(offer.copy(name = "SLOWBURN_2026"))
            assertEquals(old, model.state.value.form)
            model.toggleCollection(offer.name)
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.collectionNames to
                listOf((old.postedCollectionNames + "slowburn_2026").joinToString(", "))))
            old = model.state.value.form!!
            for (row in old.collections.filter { it.isSelected }) model.toggleCollection(row.name)
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.collectionNames to listOf("")))
            assertEquals(old.collectionNames, model.state.value.form!!.collectionNames)
            old = model.state.value.form!!
            model.addCollection(AO3CollectionOffer("closed", "Closed", AO3CollectionAccess(isOpen = false)))
            model.toggleCollection("closed") // iOS shows closed state but does not disable the row.
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.collectionNames to listOf("closed")))
            assertEquals(0, setup.client.posts)
        }
        val form = AO3WorkFormParser().parse(workFixture("ao3_work_edit"))
        assertEquals(form.collectionNames, form.copy(collections = emptyList()).postedCollectionNames)
        assertEquals("Closed to new works · Unrevealed until reveal · Anonymous", collectionStateText(
            AO3CollectionAccess(isOpen = false, isModerated = true, isUnrevealed = true, isAnonymous = true)))
        assertEquals("Moderated (a maintainer approves the work)", collectionStateText(AO3CollectionAccess(isModerated = true)))
        assertEquals("Open", collectionStateText(AO3CollectionAccess()))
        assertEquals("Open to new works (it may be moderated or unrevealed)", collectionStateText(AO3CollectionAccess(isDescribed = false)))
    }

    @Test fun giftsAreWholeTrimmedNamesUniqueIgnoringCaseAndRemoveWithoutOtherChanges() = runTest {
        for (id in forms) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            val old = model.state.value.form!!
            assertFalse(model.addGift("\u200b\n"))
            assertEquals(old, model.state.value.form)
            assertTrue(model.addGift("\u0085  Gift 星, another name \u200b"))
            val names = old.gifts + "Gift 星, another name"
            assertDelta(old, model.state.value.form!!, mapOf(AO3WorkFormField.recipients to listOf(names.joinToString(", "))))
            var before = model.state.value.form!!
            assertFalse(model.addGift("gift 星, ANOTHER NAME"))
            assertEquals(before, model.state.value.form)
            model.removeGift("Gift 星, another name")
            assertDelta(before, model.state.value.form!!, mapOf(AO3WorkFormField.recipients to listOf(old.gifts.joinToString(", "))))
            before = model.state.value.form!!
            for (name in before.gifts) model.removeGift(name)
            assertDelta(before, model.state.value.form!!, mapOf(AO3WorkFormField.recipients to listOf("")))
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
    }

    @Test fun pseudsUseServedIDsKeepTheLastOneAndBylineRemainsLiteral() = runTest {
        for (id in forms) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            var before = model.state.value.form!!
            model.togglePseud("101")
            assertEquals(before, model.state.value.form) // Last own pseud cannot be turned off.
            model.togglePseud("202")
            assertDelta(before, model.state.value.form!!, mapOf(AO3WorkFormField.authorIDs to listOf("101", "202")))
            before = model.state.value.form!!
            model.togglePseud("101")
            assertDelta(before, model.state.value.form!!, mapOf(AO3WorkFormField.authorIDs to listOf("202")))
            before = model.state.value.form!!
            model.togglePseud("202"); model.togglePseud("made up")
            assertEquals(before, model.state.value.form)
            for (value in listOf("  username (pseud) 星  ", "   ", "")) {
                before = model.state.value.form!!
                model.coauthor(value)
                assertDelta(before, model.state.value.form!!, mapOf(AO3WorkFormField.authorByline to listOf(value)))
                assertEquals(if (value.isEmpty()) "1" else "1 + 1 invited", model.state.value.form!!.creatorsValue())
            }
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
    }

    @Test fun sourceFieldsTranslationAndClearsUseIosModeledAndLandedRemainderRules() = runTest {
        for (id in forms) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            var before = model.state.value.form!!
            model.parentWork { it.copy(url = "https://example.test/source") }
            assertDelta(before, model.state.value.form!!, mapOf(AO3WorkFormField.parentURL to listOf("https://example.test/source"),
                AO3WorkFormField.parentTitle to listOf(before.parentWork.title), AO3WorkFormField.parentAuthor to listOf(before.parentWork.author),
                AO3WorkFormField.parentLanguageID to listOf(before.parentWork.languageID)))
            for ((field, edit) in listOf<Pair<String, (AO3ParentWorkDraft) -> AO3ParentWorkDraft>>(
                AO3WorkFormField.parentTitle to { it.copy(title = "  A title 星  ") },
                AO3WorkFormField.parentAuthor to { it.copy(author = "  An author  ") },
                AO3WorkFormField.parentLanguageID to { it.copy(languageID = "2") },
                AO3WorkFormField.parentTranslation to { it.copy(isTranslation = true) },
                AO3WorkFormField.parentTranslation to { it.copy(isTranslation = false) }
            )) {
                before = model.state.value.form!!
                model.parentWork(edit)
                val expected = when (field) {
                    AO3WorkFormField.parentTitle -> "  A title 星  "
                    AO3WorkFormField.parentAuthor -> "  An author  "
                    AO3WorkFormField.parentLanguageID -> "2"
                    else -> if (model.state.value.form!!.parentWork.isTranslation) "1" else "0"
                }
                assertDelta(before, model.state.value.form!!, mapOf(field to listOf(expected)))
            }
            before = model.state.value.form!!
            model.parentWork { it.copy(url = "") } // Title-only source still posts, row says None.
            assertDelta(before, model.state.value.form!!, mapOf(AO3WorkFormField.parentURL to listOf("")))
            before = model.state.value.form!!
            model.parentWork { AO3ParentWorkDraft() }
            val changed = model.state.value.form!!
            val sourceFields = setOf(AO3WorkFormField.parentURL, AO3WorkFormField.parentTitle,
                AO3WorkFormField.parentAuthor, AO3WorkFormField.parentLanguageID, AO3WorkFormField.parentTranslation)
            // iOS emits no parent text group on clear. 3bb replays the exact served fields.
            assertDelta(before, changed, sourceFields.associateWith { field -> changed.servedControls.filter { it.name == field }
                .flatMap { it.successfulValues(AO3WorkSubmitAction.Update) } })
            val ios = AO3WorkFormEncoder.iosParameters(changed, AO3WorkSubmitAction.Update)
            assertFalse(ios.any { it.first in sourceFields - AO3WorkFormField.parentTranslation })
            model.parentWork { it.copy(author = "Author alone", languageID = "2", isTranslation = true) }
            assertDelta(changed, model.state.value.form!!, emptyMap()) // Neither author nor translation alone activates the group.
            assertEquals(1, setup.client.gets.size); assertEquals(0, setup.client.posts)
        }
    }

    @Test fun collectionsReadIsOnlyOnFirstOpeningIncludingEmptyFailureAndCancellation() = runTest {
        for (id in forms) for (failure in listOf(false, true)) {
            val setup = workFormSetup()
            val model = setup.model(id).also { it.load() }
            val before = model.state.value.form!!
            assertEquals(1, setup.client.gets.size)
            setup.client.body = workFixture("ao3_collections_index")
            if (failure) setup.client.failure = AO3Error.Forbidden
            model.openCollections(); model.openCollections(); model.load()
            assertEquals(listOf(if (id == null) AO3WorkFormUrls.newWork() else AO3WorkFormUrls.editWork(id),
                AO3AccountUrls().collectionsUrl("AO3_Reader")), setup.client.gets)
            if (failure) assertEquals(before, model.state.value.form)
            else {
                assertEquals(listOf("winter_exchange", "summer_meme", "rare_pairs") + before.collectionNames,
                    model.state.value.form!!.collections.map { it.name })
                assertDelta(before, model.state.value.form!!, emptyMap())
            }
            assertTrue(model.addGift("Still usable")); assertEquals(0, setup.client.posts)
        }
        val empty = workFormSetup()
        val emptyModel = empty.model(null).also { it.load() }
        empty.client.body = "<ul class='collection index'></ul>"
        emptyModel.openCollections(); emptyModel.openCollections()
        assertEquals(2, empty.client.gets.size)
        val throwing = workFormSetup()
        val throwingModel = throwing.model(null).also { it.load() }
        throwing.client.beforeResponse = { error("Transport unavailable") }
        throwingModel.openCollections(); throwingModel.openCollections()
        assertEquals(2, throwing.client.gets.size)
        assertTrue(throwingModel.addGift("Usable after exception"))
        val setup = workFormSetup()
        val model = setup.model(null).also { it.load() }
        setup.client.beforeResponse = { awaitCancellation() }
        val loading = launch { model.openCollections() }
        runCurrent(); loading.cancel(); runCurrent()
        setup.client.beforeResponse = {}
        model.openCollections()
        assertEquals(2, setup.client.gets.size)
    }

    @Test fun collectionMergeMatchesOnlySlugsAndKeepsEditsMadeWhileLoading() = runTest {
        val form = AO3WorkFormParser().parse(workFixture("ao3_work_edit")).copy(collectionNames = listOf("salt", "gift_swap_2025"))
        val merged = form.applyingCollectionStates(listOf(AO3CollectionOffer("salt_exchange", "Salt"), AO3CollectionOffer("Salt", "Salt Flats")))
        assertEquals(listOf("salt_exchange", "Salt", "gift_swap_2025"), merged.collections.map { it.name })
        assertEquals(listOf(false, true, true), merged.collections.map { it.isSelected })
        assertEquals(listOf("Salt", "gift_swap_2025"), merged.postedCollectionNames)
        val setup = workFormSetup()
        val model = setup.model(995006L).also { it.load() }
        val release = CompletableDeferred<Unit>()
        setup.client.body = workFixture("ao3_collections_index")
        setup.client.beforeResponse = { release.await() }
        val loading = launch { model.openCollections() }
        runCurrent()
        model.toggleCollection("lantern_exchange")
        model.addCollection(AO3CollectionOffer("new_choice", "New")); model.toggleCollection("new_choice")
        model.addCollection(AO3CollectionOffer("unticked_hit", "Unticked", AO3CollectionAccess(isDescribed = false)))
        release.complete(Unit); loading.join()
        assertEquals(listOf("star_atlas", "new_choice"), model.state.value.form!!.postedCollectionNames)
        assertFalse(model.state.value.form!!.collections.last().isSelected)
        assertFalse(model.state.value.form!!.collections.last().access.isDescribed)
        assertEquals(0, setup.client.posts)
    }

    @Test fun virtualClockOneReadPerSettledTermNoOpeningReadAndFailureStaysUsable() = runTest {
        val client = AssociationSuggestionsClient()
        val search = WritingCollectionsSearchState(AO3TagAutocompleteRepository(client), this)
        runCurrent(); assertTrue(client.gets.isEmpty())
        search.type("replaced"); advanceTimeBy(299); search.type("  demo 星  ")
        advanceTimeBy(299); runCurrent(); assertTrue(client.gets.isEmpty())
        advanceTimeBy(1); runCurrent()
        assertEquals(1, client.gets.size)
        assertEquals("demo 星", client.gets.single().toHttpUrl().queryParameter("term"))
        assertEquals(listOf("demo_one", "demo_two"), search.state.value.offers.map { it.name })
        assertEquals(listOf("Demo One", "Demo Two"), search.state.value.offers.map { it.title })
        assertTrue(search.state.value.offers.all { !it.isSelected && !it.access.isDescribed })
        search.type("  demo 星  "); advanceTimeBy(300); runCurrent(); assertEquals(1, client.gets.size)
        search.type("none"); assertTrue(search.state.value.offers.isEmpty())
        advanceTimeBy(300); runCurrent(); assertTrue(search.state.value.offers.isEmpty())
        search.type("fail"); advanceTimeBy(300); runCurrent(); assertTrue(search.state.value.offers.isEmpty())
        search.type("x"); advanceTimeBy(300); runCurrent(); assertEquals(4, client.gets.size)
        search.type("   "); advanceTimeBy(300); runCurrent(); assertEquals(4, client.gets.size)
        search.type("leaving"); search.close(); advanceTimeBy(300); runCurrent(); assertEquals(4, client.gets.size)
        assertEquals(0, client.posts)
    }

    @Test fun changedQueryAndClosingCancelInflightSuggestionsAndSessionChangeDiscardsPrivateOffers() = runTest {
        val client = AssociationSuggestionsClient().apply { beforeResponse = { awaitCancellation() } }
        val search = WritingCollectionsSearchState(AO3TagAutocompleteRepository(client), this)
        search.type("demo"); advanceTimeBy(300); runCurrent()
        search.type(""); runCurrent(); assertEquals(1, client.cancelled)
        search.type("demo"); advanceTimeBy(300); runCurrent()
        search.close(); runCurrent(); assertEquals(2, client.cancelled)
        assertTrue(search.state.value.offers.isEmpty())
        val setup = workFormSetup()
        val model = setup.model(null).also { it.load() }
        val old = model.state.value.form
        setup.client.body = workFixture("ao3_collections_index")
        setup.client.beforeResponse = { setup.auth.logout() }
        val read = launch { model.openCollections() }
        read.join()
        assertTrue(read.isCancelled)
        model.addGift("late"); model.coauthor("late"); model.newSeries("late")
        model.parentWork { it.copy(title = "late") }; model.togglePseud("202")
        assertEquals(old, model.state.value.form)
        val signedOut = workFormSetup(false)
        val absent = signedOut.model(null)
        absent.load(); absent.openCollections()
        assertTrue(signedOut.client.gets.isEmpty())
    }

    @Test fun collectionAutocompleteUsesRequiredStringIDsAndNoExtraReadsOrMetadata() = runTest {
        var body = """[{"id":"\u200b slug \u200b","name":"Display (slug)","moderated":true},{"id":"","name":"Skip"}]"""
        val reads = mutableListOf<String>()
        val client = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                reads += url
                assertTrue(headers.isEmpty()) // Anonymous autocomplete, never an account cookie.
                return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), body))
            }
        }
        val repository = AO3TagAutocompleteRepository(client)
        val offer = (repository.openCollections("  星 & water  ") as AO3Result.Success).value.single()
        assertEquals("slug", offer.name); assertEquals("Display", offer.title)
        assertFalse(offer.access.isDescribed); assertFalse(offer.access.isModerated)
        assertEquals("星 & water", reads.single().toHttpUrl().queryParameter("term"))
        assertEquals("/autocomplete/open_collection_names", reads.single().toHttpUrl().encodedPath)
        for (malformed in listOf("""[{"id":123,"name":"A"}]""", """[{"id":"a"}]""", "not json")) {
            body = malformed
            val result = repository.openCollections("x")
            assertTrue(result is AO3Result.Failure && result.error is AO3Error.Parse)
        }
        assertEquals(4, reads.size)
    }
}

internal class AssociationSuggestionsClient : AO3Client, AO3FormPostClient {
    val gets = mutableListOf<String>()
    var posts = 0
    var cancelled = 0
    var beforeResponse: suspend () -> Unit = {}
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        try { beforeResponse() } catch (e: kotlinx.coroutines.CancellationException) { cancelled++; throw e }
        val term = url.toHttpUrl().queryParameter("term")
        if (term == "fail") return AO3Result.Failure(AO3Error.Forbidden)
        val body = if (term == "none") "[]" else """[{"id":"demo_one","name":"Demo One (demo_one)"},{"id":"demo_two","name":"Demo Two (demo_two)"}]"""
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), body))
    }
    override suspend fun postForm(url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        posts++; error("Association pickers must never send a write")
    }
}
