package io.github.cidy02.kudos.comments

import io.github.cidy02.kudos.network.ao3.displayMessage

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterIndexRepository
import io.github.cidy02.kudos.network.ao3.chapters.AO3ChapterRef
import io.github.cidy02.kudos.network.ao3.comments.AO3Comment
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentAuthor
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentRepository
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentTarget
import io.github.cidy02.kudos.network.ao3.comments.CommentDraftStore
import io.github.cidy02.kudos.network.ao3.comments.CommentDraftIdentity
import io.github.cidy02.kudos.network.ao3.comments.CommentSubmissionStore
import io.github.cidy02.kudos.network.ao3.comments.CommentSubmissionKey
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.network.ao3.writes.success
import io.github.cidy02.kudos.network.ao3.writes.writeResource
import java.io.File
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.cancel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Audit A32, items 1, 4, 5 and 8: a composer belongs to what it was opened for and to the reader who
 * opened it, and the reader is a session, not a name. Every lookup that has to answer late is held by
 * an explicit gate (the draft store's read, a GET, the POST). The repository parses pages on its own
 * dispatcher, which this brief may not change, so waiting for a page still polls in real time.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class CommentsViewModelContextTest {
    @get:Rule
    val tmp = TemporaryFolder()

    private val testDispatcher = StandardTestDispatcher()
    private lateinit var store: GatedStore
    private lateinit var drafts: CommentDraftStore
    private val workId = 123L
    private val work = AO3CommentTarget.Work(workId)
    private val chapter = AO3CommentTarget.Chapter(workId, 77L)
    private val basic get() = success(writeResource("ao3/comments/comments_basic.html"))

    @Before
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        store = GatedStore(PreferenceDataStoreFactory.create(
            scope = TestScope(testDispatcher), produceFile = { File(tmp.root, "context.preferences_pb") }))
        drafts = CommentDraftStore(store)
    }

    @After
    fun tearDown() {
        // Nothing of one test's model is left to answer during the next: a read parsed off the test's
        // clock would otherwise come back to whichever test is running by then.
        models.forEach { it.viewModelScope.cancel() }
        idle()
        Dispatchers.resetMain()
    }

    private fun idle() = testDispatcher.scheduler.advanceUntilIdle()

    private fun until(what: String, done: () -> Boolean) {
        for (attempt in 1..500) {
            idle()
            if (done()) return
            Thread.sleep(10)
        }
        throw AssertionError("never happened: $what")
    }

    @Test fun chapterOpeningResolvesBeforeItsOnlyCommentsReadAndReturnDoesNotReadAll() {
        val gate = CompletableDeferred<Unit>()
        val session = Session(basic)
        val index = object : AO3Client {
            var reads = 0
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                reads++
                gate.await()
                return success("<ol class='chapter index'><li><a href='/works/123/chapters/77'>1. First</a></li></ol>")
            }
        }
        val model = CommentsViewModel(AO3CommentRepository(PublicPage(basic), session), work,
            initialChapterPosition = 1, chapterIndexRepository = AO3ChapterIndexRepository(index),
            sessionGeneration = { session.generation }, currentUsername = { session.name }).also { models += it }
        idle()
        assertEquals(1, index.reads)
        assertEquals(emptyList<String>(), session.urls)
        gate.complete(Unit)
        until("chapter comments loaded") { loaded(model) }
        assertEquals(chapter, model.currentTarget.value)
        assertEquals(CommentScope.ByChapter, model.scope.value)
        assertEquals(1, session.urls.size)
        org.junit.Assert.assertTrue(session.urls.single().contains("/chapters/77"))
        model.syncViewer() // Reappearing in the same session.
        idle()
        assertEquals(1, session.urls.size)
    }

    @Test fun unavailableInitialChapterIndexFallsBackToExactlyOneAllCommentsRead() {
        val session = Session(basic)
        var indexes = 0
        val index = object : AO3Client {
            override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
                indexes++
                return AO3Result.Failure(AO3Error.NotFound)
            }
        }
        val model = CommentsViewModel(AO3CommentRepository(PublicPage(basic), session), work,
            initialChapterPosition = 2, chapterIndexRepository = AO3ChapterIndexRepository(index),
            currentUsername = { session.name }).also { models += it }
        until("fallback comments loaded") { loaded(model) }
        assertEquals(1, indexes)
        assertEquals(1, session.urls.size)
        assertEquals(work, model.currentTarget.value)
    }

    private val submissions = CommentSubmissionStore()
    private val models = mutableListOf<CommentsViewModel>()
    private fun model(session: Session, focused: Long? = null, position: Int? = null) = CommentsViewModel(
        AO3CommentRepository(publicClient = PublicPage(basic), authenticatedClient = session),
        work, drafts, focused, position, { session.generation }, submissions = submissions) { session.name }.also { models += it }

    private fun loaded(viewModel: CommentsViewModel) = viewModel.state.value is CommentsUiState.Loaded

    private fun pageOf(viewModel: CommentsViewModel) = (viewModel.state.value as? CommentsUiState.Loaded)?.thread?.currentPage
    private fun idsOf(viewModel: CommentsViewModel) =
        (viewModel.state.value as CommentsUiState.Loaded).thread.comments.mapNotNull { it.numericId }

    /**
     * 3df (iOS `CommentsModel.load`): comments open on the newest, which AO3 keeps on a work's last
     * page. One read of page 1 for the count, one of the last page, and both are kept while the
     * screen is open, so the other order and the way back ask AO3 nothing.
     */
    @Test
    fun newestFirstReadsTheFirstPageForTheCountThenTheLastAndKeepsBoth() {
        val threePages = success(io.github.cidy02.kudos.network.ao3.writing.workFixture("ao3_comments_page"))
        val session = Session(threePages)
        val viewModel = CommentsViewModel(AO3CommentRepository(publicClient = PublicPage(threePages), authenticatedClient = session),
            work, drafts, null, null, { session.generation }) { session.name }.also { models += it }
        until("the last page is on screen") { pageOf(viewModel) == 3 }
        assertEquals(2, session.urls.size)
        assertEquals(false, "page=" in session.urls[0])
        assertEquals(true, "page=3" in session.urls[1])
        assertEquals("newest at the top", idsOf(viewModel).sortedDescending(), idsOf(viewModel))

        viewModel.load(page = 1)
        until("the first page, from what was kept") { pageOf(viewModel) == 1 }
        viewModel.setOrder(CommentOrder.OldestFirst)
        until("oldest first starts on the first page") { pageOf(viewModel) == 1 && idsOf(viewModel) == idsOf(viewModel).sorted() }
        viewModel.setOrder(CommentOrder.NewestFirst)
        until("newest first is the last page again") { pageOf(viewModel) == 3 }
        assertEquals("nothing more was asked of AO3", 2, session.urls.size)

        viewModel.viewModelScope.launch { viewModel.refresh() }
        until("pull to refresh reads the page on screen") { session.urls.size == 3 }
        assertEquals(true, "page=3" in session.urls[2])
    }

    @Test
    fun aWorkWithOnePageOfCommentsIsOneRead() {
        val session = Session(basic)
        val viewModel = model(session)
        until("loaded") { loaded(viewModel) }
        assertEquals(1, pageOf(viewModel))
        assertEquals(1, session.urls.size)
    }

    @Test
    fun anUnrecognised200PageStopsNewestPageDiscoveryAndRetryCanLoadTheEmptyList() {
        var html = "<html><body><p>This work could have adult content.</p>" +
            "<ol class='pagination'><li>1</li><li>3</li></ol></body></html>"
        val session = Session(basic) { url -> success(html, url = url) }
        val viewModel = model(session)
        until("the parse error") { viewModel.state.value is CommentsUiState.Error }
        assertEquals("an invalid first page cannot discover a newest page", 1, session.urls.size)

        html = writeResource("ao3/comments/comments_empty.html")
        viewModel.retry()
        until("the recognised empty page") { loaded(viewModel) }
        assertEquals(emptyList<Long>(), idsOf(viewModel))
        assertEquals(2, session.urls.size)
    }

    private fun reply(id: Long) = AO3Comment(
        id = "comment_$id", author = AO3CommentAuthor(name = "Someone"), date = "2026-08-03", body = "Stub", canReply = true)

    /** The Inbox's Reply: the thread first, then the reply composer for that very comment. */
    @Test
    fun theInboxsReplyOpensTheComposerForItsCommentOnceTheThreadIsOnScreen() = runTest(testDispatcher) {
        val viewModel = model(Session(basic), focused = 2L)
        viewModel.replyWhenLoaded(2L)
        assertEquals("nothing opens before there is a page", false, viewModel.composerPresented.value)
        until("the reply composer") { viewModel.composerPresented.value }
        assertEquals(2L, viewModel.replyTarget.value?.commentId)
        assertEquals("comment_2", viewModel.composerParent.value?.id)

        // Asked once: closing it and reading the page again does not open it a second time.
        viewModel.closeComposer(); idle()
        viewModel.load(1, 2L)
        until("the page again") { loaded(viewModel) }
        idle()
        assertEquals(false, viewModel.composerPresented.value)
    }

    @Test
    fun aReplyToACommentThePageDoesNotHoldOpensNothing() = runTest(testDispatcher) {
        val viewModel = model(Session(basic), focused = 999L)
        viewModel.replyWhenLoaded(999L)
        until("the page") { loaded(viewModel) }
        idle()
        assertEquals("not a new comment on the work in its place", false, viewModel.composerPresented.value)
        assertEquals(null, viewModel.replyTarget.value)
    }

    @Test
    fun aChangeOfReaderForgetsTheReplyThatWasAskedFor() = runTest(testDispatcher) {
        val session = Session(basic)
        val held = CompletableDeferred<Unit>()
        session.getGate = { held }
        val viewModel = model(session, focused = 2L)
        viewModel.replyWhenLoaded(2L)
        testDispatcher.scheduler.runCurrent()
        session.name = "bob"; session.generation = 2
        viewModel.syncViewer()
        session.getGate = { null }; held.complete(Unit)
        until("the page for the new reader") { loaded(viewModel) }
        idle()
        assertEquals(false, viewModel.composerPresented.value)
    }

    /** A1-1. "Write a comment", then a chapter chosen before the work's draft has been read. */
    @Test
    fun aComposerStillReadingItsDraftDoesNotOpenOnTheChapterTheReaderMovedTo() = runTest(testDispatcher) {
        drafts.saveDraft("for the work", workId, parentId = null, username = "alice"); idle()
        val viewModel = model(Session(basic))
        until("the first page") { viewModel.isDraftRestored.value }

        val held = CompletableDeferred<Unit>().also { store.gate = it }
        viewModel.openComposer()
        testDispatcher.scheduler.runCurrent() // the lookup has begun and waits on the store
        assertEquals(false, viewModel.composerPresented.value)
        viewModel.selectChapter(AO3ChapterRef(77L, 3, "Three"))
        store.gate = null; held.complete(Unit)
        until("the chapter's page") { viewModel.currentTarget.value == chapter && loaded(viewModel) }

        // The sheet used to open here, holding the work's draft over the chapter.
        assertEquals(false, viewModel.composerPresented.value)
        assertEquals(null, viewModel.composerTarget.value)

        // Asked for again it is the chapter's own, and what is typed in it is the chapter's.
        viewModel.openComposer(); idle()
        assertEquals(true, viewModel.composerPresented.value)
        assertEquals(chapter, viewModel.composerTarget.value)
        assertEquals("", viewModel.draft.value)
        viewModel.updateDraft("for the chapter"); idle()
        assertEquals("for the chapter", drafts.getDraft(workId, chapterId = 77L, parentId = null, username = "alice"))
        assertEquals("for the work", drafts.getDraft(workId, parentId = null, username = "alice"))
    }

    @Test fun secondTapWhileInFlightDoesNothingAndSuccessClearsOnlyItsChapterVariants() = runTest(testDispatcher) {
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { viewModel.isDraftRestored.value }
        drafts.saveDraft("chapter variant", workId, chapterId = 77, username = "alice")
        drafts.saveDraft("another account", workId, chapterId = 77, username = "bob")
        drafts.saveDraft("another parent", workId, parentId = 101, username = "alice")
        viewModel.openComposer(); idle()
        viewModel.updateDraft("single flight body"); idle()
        val held = CompletableDeferred<Unit>().also { session.postGate = it }
        viewModel.submitComment()
        // No scheduler turn between taps: admission must be synchronous.
        assertEquals(true, viewModel.submitting.value)
        viewModel.submitComment()
        until("one held POST") { session.posts.size == 1 }
        viewModel.submitComment(); idle()
        assertEquals(1, session.posts.size)
        held.complete(Unit)
        until("posted") { !viewModel.submitting.value && !viewModel.composerPresented.value }
        assertEquals(null, drafts.getDraft(workId, username = "alice"))
        assertEquals(null, drafts.getDraft(workId, chapterId = 77, username = "alice"))
        assertEquals("another account", drafts.getDraft(workId, chapterId = 77, username = "bob"))
        assertEquals("another parent", drafts.getDraft(workId, parentId = 101, username = "alice"))
    }

    @Test fun lostAnswerSurvivesReopeningAndUnknownCheckNeverPostsAgain() = runTest(testDispatcher) {
        val session = Session(basic)
        session.postAnswer = AO3Result.Failure(AO3Error.Network("lost answer"))
        val first = model(session)
        until("the first page") { first.isDraftRestored.value }
        first.openComposer(); idle()
        first.updateDraft("ambiguous original body"); idle()
        // The form read before the POST is valid; verification after it gets an interstitial,
        // never a cache hit. (Set before submitting, the form read got it too and nothing posted.)
        session.answerAfterPost = success("<p>Maintenance</p>")
        first.submitComment()
        until("unknown verification") { session.posts.size == 1 && !first.submitting.value && first.canReverify.value }
        assertEquals("ambiguous original body", drafts.getDraft(workId, username = "alice"))
        first.closeComposer(); idle()
        first.viewModelScope.cancel()
        val reads = session.urls.size
        val reopened = model(session)
        reopened.openComposer()
        until("reopened verification") { session.urls.size > reads + 1 && !reopened.submitting.value && reopened.canReverify.value }
        reopened.updateDraft("edited while unresolved"); idle()
        val checkGate = CompletableDeferred<Unit>()
        session.getGate = { checkGate }
        val beforeCheck = session.urls.size
        reopened.reverify()
        until("verification GET held") { session.urls.size > beforeCheck }
        assertEquals(true, reopened.verifying.value)
        assertEquals(true, reopened.submitting.value)
        reopened.reverify(); reopened.submitComment(); idle()
        assertEquals(1, session.posts.size)
        session.getGate = { null }; checkGate.complete(Unit)
        until("rechecked") { !reopened.submitting.value }
        assertEquals(false, reopened.verifying.value)
        assertEquals(1, session.posts.size)
        val original = CommentSubmissionKey.of(work, null, "ambiguous original body", "alice")
        assertEquals(CommentSubmissionStore.Phase.Ambiguous, submissions.entry(original)?.phase)
        // A clean authenticated miss releases only the original and never automatically posts.
        session.getAnswer = basic
        reopened.reverify()
        until("authoritative absence") { !reopened.submitting.value && !reopened.canReverify.value }
        assertEquals(null, submissions.entry(original))
        assertEquals(1, session.posts.size)
        reopened.updateDraft("ambiguous original body"); idle()
        reopened.submitComment()
        until("explicit second attempt") { session.posts.size == 2 && !reopened.submitting.value }
        assertEquals(2, session.posts.size)
    }

    // iOS guardAdoptShowsIdleForAKeyTheStoreHasNoEntryFor: unrelated drafts have no Check Again target.
    @Test fun adoptingAFreshReplyClearsTheOldVerificationWithoutReleasingItsDuplicateBlock() = runTest(testDispatcher) {
        val session = Session(basic)
        session.postAnswer = AO3Result.Failure(AO3Error.Network("lost answer"))
        val viewModel = model(session)
        until("initial page") { viewModel.isDraftRestored.value }
        viewModel.openComposer(); idle()
        viewModel.updateDraft("original unresolved body"); idle()
        session.answerAfterPost = success("<p>Maintenance</p>")
        viewModel.submitComment()
        until("unknown verification") { !viewModel.submitting.value && viewModel.canReverify.value }
        val key = CommentSubmissionKey.of(work, null, "original unresolved body", "alice")
        viewModel.closeComposer(); idle()
        assertEquals(false, viewModel.canReverify.value)
        viewModel.startReply(AO3Comment(id = "comment_101", author = AO3CommentAuthor(name = "Other"),
            date = "2026-08-03", body = "Another comment", canReply = true))
        idle()
        assertEquals(false, viewModel.canReverify.value)
        val reads = session.urls.size
        viewModel.reverify(); idle()
        assertEquals(reads, session.urls.size)
        assertEquals(1, session.posts.size)
        assertEquals(CommentSubmissionStore.Phase.Ambiguous, submissions.entry(key)?.phase)
        viewModel.closeComposer(); idle()
        viewModel.openComposer()
        until("original adopted again") { !viewModel.submitting.value && viewModel.canReverify.value }
    }

    @Test fun definitiveRefusalsAndOfflineFailuresKeepTheDraftAndPermitOnlyAnExplicitRetry() = runTest(testDispatcher) {
        for ((index, error) in listOf(AO3Error.Network("offline", offline = true), AO3Error.RateLimited(1000),
            AO3Error.Validation("Rejected")).withIndex()) {
            val session = Session(basic).also { it.postAnswer = AO3Result.Failure(error) }
            val model = model(session)
            until("initial page") { model.isDraftRestored.value }
            model.openComposer(); idle()
            model.updateDraft("definitive failure $index"); idle()
            val reads = session.urls.size
            model.submitComment()
            until("definitive refusal") { session.posts.size == 1 && !model.submitting.value }
            assertEquals(reads + 1, session.urls.size) // CSRF only: no ambiguous verification.
            assertEquals(false, model.canReverify.value)
            assertEquals("definitive failure $index", drafts.getDraft(workId, username = "alice"))
            assertEquals(null, submissions.entry(CommentSubmissionKey.of(work, null, "definitive failure $index", "alice")))
            model.submitComment()
            until("explicit retry") { session.posts.size == 2 && !model.submitting.value }
            model.closeComposer(); idle()
        }
    }

    @Test fun anUnnamedSessionsDraftsMoveToItsVerifiedNameWithoutReplacingExistingDrafts() = runTest(testDispatcher) {
        val session = Session(basic).also { it.name = ""; it.generation = 3 }
        val unnamed = CommentDraftIdentity.unnamedSession(3)
        assertEquals(unnamed, CommentDraftIdentity.unnamedSession(3))
        assertEquals(false, unnamed == CommentDraftIdentity.unnamedSession(4))
        drafts.saveDraft("old launch", 43, username = "unknown-session:3")
        drafts.saveDraft("alice's reply", workId, parentId = 101, username = "alice")
        drafts.saveDraft("bob's reply", workId, parentId = 101, username = "bob")
        val viewModel = model(session)
        until("the unnamed page") { viewModel.isDraftRestored.value }
        viewModel.startReply(reply(101)); idle()
        viewModel.updateDraft("typed offline")
        // Even the save queued in this frame must land before the handoff.
        session.name = "alice"; session.generation = 4
        viewModel.syncViewer(); idle()
        assertEquals("typed offline\n\nalice's reply", drafts.getDraft(workId, parentId = 101, username = "alice"))
        assertEquals(null, drafts.getDraft(workId, parentId = 101, username = unnamed))
        assertEquals("bob's reply", drafts.getDraft(workId, parentId = 101, username = "bob"))
        assertEquals("old launch", drafts.getDraft(43, username = "unknown-session:3"))
        assertEquals(null, drafts.getDraft(43, username = "alice"))
    }

    @Test fun verifyingAnUnnamedSessionMovesDraftsEvenWhenTheCommentsScreenHasClosed() = runTest(testDispatcher) {
        var verified = false
        val auth = io.github.cidy02.kudos.auth.AO3AuthRepository(
            io.github.cidy02.kudos.auth.MemorySessionStore(io.github.cidy02.kudos.auth.testSession("")),
            io.github.cidy02.kudos.auth.MemoryCookieStore(),
            sessionValidator = io.github.cidy02.kudos.auth.AO3SessionValidating { session ->
                if (!verified) throw java.io.IOException("offline")
                io.github.cidy02.kudos.auth.AO3SessionValidation.Valid(session.copy(username = "alice"))
            }, commentDraftStore = drafts
        )
        auth.restoreSession()
        val identity = CommentDraftIdentity.unnamedSession(auth.generation.value)
        drafts.saveDraft("a closed screen's draft", workId, username = identity)
        verified = true
        auth.verifySession()
        assertEquals("a closed screen's draft", drafts.getDraft(workId, username = "alice"))
        assertEquals(null, drafts.getDraft(workId, username = identity))
    }

    /** iOS `composerContext`: a composer already open keeps the work it was opened for. */
    @Test
    fun anOpenComposerKeepsWhatItWasOpenedForWhenTheScreenMovesToAChapter() = runTest(testDispatcher) {
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { viewModel.isDraftRestored.value }
        viewModel.openComposer(); idle()
        viewModel.updateDraft("typed for the work"); idle()

        viewModel.openOnChapter(AO3ChapterRef(77L, 3, "Three")) // the reader's button, answering late
        until("the chapter's page") { viewModel.currentTarget.value == chapter && loaded(viewModel) }
        viewModel.updateDraft("typed for the work, and more"); idle()

        assertEquals(true, viewModel.composerPresented.value)
        assertEquals(work, viewModel.composerTarget.value)
        assertEquals("typed for the work, and more", drafts.getDraft(workId, parentId = null, username = "alice"))
        assertEquals(null, drafts.getDraft(workId, chapterId = 77L, parentId = null, username = "alice"))

        viewModel.submitComment()
        until("the send") { session.posts.size == 1 && !viewModel.submitting.value && !viewModel.composerPresented.value }
        assertEquals(null, drafts.getDraft(workId, parentId = null, username = "alice"))
    }

    /** A32-1 and A32-5. The same name signed in again is another reader. */
    @Test
    fun aDraftReadForOneSessionDoesNotOpenForTheNext() = runTest(testDispatcher) {
        drafts.saveDraft("from the first session", workId, parentId = null, username = "alice"); idle()
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { viewModel.isDraftRestored.value }

        val held = CompletableDeferred<Unit>().also { store.gate = it }
        viewModel.openComposer()
        testDispatcher.scheduler.runCurrent()
        session.generation = 2 // signed out and in again, under the same name
        store.gate = null; held.complete(Unit); idle()
        assertEquals(false, viewModel.composerPresented.value)

        // The screen then says so: everything is read again, once.
        val reads = session.urls.size
        assertEquals(true, viewModel.syncViewer())
        until("the page, read again") { session.urls.size > reads && loaded(viewModel) }
        assertEquals(false, viewModel.syncViewer())
    }

    /** What was typed is saved as the reader who typed it, and the next reader's screen starts clean. */
    @Test
    fun aNewReaderGetsACleanScreenAndTheLastOnesTextStaysTheirs() = runTest(testDispatcher) {
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { viewModel.isDraftRestored.value }
        viewModel.startReply(reply(101L)); idle()
        viewModel.updateDraft("alice's reply"); idle()

        session.name = "bob"; session.generation = 2
        assertEquals(true, viewModel.syncViewer()); idle()

        assertEquals(false, viewModel.composerPresented.value)
        assertEquals(null, viewModel.replyTarget.value)
        assertEquals("", viewModel.draft.value)
        assertEquals("alice's reply", drafts.getDraft(workId, parentId = 101L, username = "alice"))
        assertEquals(null, drafts.getDraft(workId, parentId = 101L, username = "bob"))
        // A reply tapped on a row of the last reader's page, before the screen has said so, opens nothing.
        session.name = "carol"; session.generation = 3
        viewModel.startReply(reply(101L)); idle()
        assertEquals(false, viewModel.composerPresented.value)
    }

    /** A32-1. The send answers after its sheet was dismissed and a reply was opened. */
    @Test
    fun aSendThatAnswersAfterAnotherComposerOpenedClearsItsOwnDraftOnly() = runTest(testDispatcher) {
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { viewModel.isDraftRestored.value }
        viewModel.openComposer(); idle()
        viewModel.updateDraft("a comment on the work"); idle()

        val held = CompletableDeferred<Unit>().also { session.postGate = it }
        viewModel.submitComment()
        until("the POST, held") { session.posts.size == 1 }
        viewModel.closeComposer()
        viewModel.startReply(reply(101L)); idle()
        viewModel.updateDraft("a reply, still being typed"); idle()
        session.postGate = null; held.complete(Unit)
        until("the verdict") { !viewModel.submitting.value && loaded(viewModel) && viewModel.message.value != null }

        assertEquals(1, session.posts.size)
        // Its own slot is cleared: AO3 has the comment.
        assertEquals(null, drafts.getDraft(workId, parentId = null, username = "alice"))
        // The reply opened since is untouched: still open, still a reply, its text in the field and stored.
        assertEquals(true, viewModel.composerPresented.value)
        assertEquals(101L, viewModel.replyTarget.value?.commentId)
        assertEquals("a reply, still being typed", viewModel.draft.value)
        assertEquals("a reply, still being typed", drafts.getDraft(workId, parentId = 101L, username = "alice"))
    }

    /** iOS `staleSuccessfulSubmitCannotClearOrCloseTheNewAccountsComposer` (A59). */
    @Test
    fun aSuccessThatAnswersAfterAnAccountSwitchTouchesNeitherAccountsDraft() = runTest(testDispatcher) {
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { viewModel.isDraftRestored.value }
        viewModel.openComposer(); idle()
        viewModel.updateDraft("Alice draft"); idle()

        val held = CompletableDeferred<Unit>().also { session.postGate = it }
        viewModel.submitComment()
        until("the POST, held") { session.posts.size == 1 }
        session.name = "bob"; session.generation = 2
        assertEquals(true, viewModel.syncViewer()); idle()
        until("Bob's page") { loaded(viewModel) }
        viewModel.openComposer(); idle()
        viewModel.updateDraft("Bob draft"); idle()
        session.postGate = null; held.complete(Unit)
        until("the stale answer") { !viewModel.submitting.value }
        idle()

        assertEquals(true, viewModel.composerPresented.value)
        assertEquals("Bob draft", viewModel.draft.value)
        assertEquals("Alice draft", drafts.getDraft(workId, parentId = null, username = "alice"))
        assertEquals("Bob draft", drafts.getDraft(workId, parentId = null, username = "bob"))
    }

    /** Codex's A59 review: the session ends while a success is clearing its draft. */
    @Test
    fun aSuccessWhoseDraftClearOutlastsTheSessionPublishesNothing() = runTest(testDispatcher) {
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { viewModel.isDraftRestored.value }
        viewModel.openComposer(); idle()
        viewModel.updateDraft("Alice comment"); idle()

        val held = CompletableDeferred<Unit>().also { store.writeGate = it }
        viewModel.submitComment()
        until("the POST") { session.posts.size == 1 }
        idle() // the success is now clearing the draft, held
        session.name = "bob"; session.generation = 2
        assertEquals(true, viewModel.syncViewer()); idle()
        store.writeGate = null; held.complete(Unit); idle()
        until("the held clear") { !viewModel.submitting.value }

        assertEquals(1, session.posts.size)
        assertEquals(null, viewModel.message.value)
        assertEquals(false, viewModel.composerPresented.value)
    }

    /** An edit has no draft slot: its success must not clear the new comment waiting in the work's. */
    @Test
    fun aSavedEditLeavesTheNewCommentDraftAlone() = runTest(testDispatcher) {
        drafts.saveDraft("a new comment, waiting", workId, parentId = null, username = "alice"); idle()
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { viewModel.isDraftRestored.value }
        viewModel.startEdit(reply(1L).copy(editPath = "/comments/1/edit")); idle()
        viewModel.updateDraft("the comment, edited"); idle()
        viewModel.submitComment()
        until("the edit") { session.posts.size == 1 && !viewModel.submitting.value && !viewModel.composerPresented.value }
        assertEquals("a new comment, waiting", drafts.getDraft(workId, parentId = null, username = "alice"))
    }

    private fun li(id: Int, chapter: Int? = null, vararg replies: String) =
        "<li id=\"comment_$id\" class=\"comment\"><h4 class=\"heading byline\"><a rel=\"author\" href=\"/users/U$id\">U$id</a>" +
            (chapter?.let { " <span class=\"parent\">on <a href=\"/works/123/chapters/$it\">Chapter 3</a></span>" } ?: "") +
            "</h4><p class=\"datetime\">1 Jan 2026</p><blockquote class=\"userstuff\"><p>c$id</p></blockquote>" +
            (if (replies.isEmpty()) "" else "<ol class=\"thread\">" + replies.joinToString("") + "</ol>") + "</li>"
    private fun page(vararg roots: String) =
        success("<html><body class=\"logged-in\"><div id=\"comments_placeholder\"><ol class=\"thread\">" +
            roots.joinToString("") + "</ol></div></body></html>")

    /** The ids of the rows the list would draw with every conversation opened, as the screen builds them. */
    private fun drawn(viewModel: CommentsViewModel): List<String> {
        val roots = (viewModel.state.value as CommentsUiState.Loaded).thread.comments
        return CommentConversationBuilder.rows(
            roots = roots,
            repliesByRoot = roots.associate { (it.numericId ?: 0L) to CommentThreadGeometry.flattenedReplies(it) },
            expandedRootIds = roots.mapNotNull { it.numericId }.toSet(),
            visibleReplyCounts = roots.mapNotNull { it.numericId }.associateWith { 1000 }
        ).map { it.item.id }.filter { it.startsWith("post-") }
    }

    /**
     * A32-4. The thread and the chapter's page overlap below the top level. (1) The thread's root is a
     * reply on the page: the whole thread was put first and that root drawn twice, which crashes the
     * list. (2) A comment inside the thread is a root on the page: the thread was put first with that
     * comment pruned, and the comment asked for, beneath it, went with it.
     */
    @Test
    fun theCommentAskedForIsDrawnOnceWhereverThePageHoldsPartOfItsThread() = runTest(testDispatcher) {
        val asked = 30L
        val shapes = listOf(
            page(li(20, 77, li(30))) to page(li(10, null, li(20))),
            page(li(40, 77, li(20, null, li(30)))) to page(li(20))
        )
        for ((thread, chapterPage) in shapes) {
            val session = Session(basic) { url -> if (url.endsWith("/comments/$asked")) thread else chapterPage }
            val viewModel = model(session, focused = asked, position = 3)
            until("the chapter's page") { session.urls.size >= 2 && loaded(viewModel) && viewModel.currentTarget.value == chapter }

            val rows = drawn(viewModel)
            assertEquals("post-comment_$asked", rows.first())
            assertEquals(rows, rows.distinct())
            assertEquals(true, "post-comment_20" in rows)
        }
    }

    /** A30-7, as A32-8 asks: the root says chapter 77 and the reply asked for says 88. The root's is read. */
    @Test
    fun theChapterIsTheOneTheThreadsRootNamesNotTheReplys() = runTest(testDispatcher) {
        val session = Session(basic) { url -> if (url.endsWith("/comments/2")) page(li(1, 77, li(2, 88))) else page(li(9)) }
        val viewModel = model(session, focused = 2L, position = 8)
        until("the chapter's page") { session.urls.size >= 2 && loaded(viewModel) }
        assertEquals(true, "/chapters/77" in session.urls[1])
        assertEquals(true, session.urls.none { "/chapters/88" in it })
    }

    /** A30-5, as A32-8 asks: "All comments" chosen while either of Chapter Comments' two reads is out. */
    @Test
    fun allCommentsChosenWhileEitherChapterCommentsReadIsHeldStands() = runTest(testDispatcher) {
        for (holdTheChapterPage in listOf(false, true)) {
            fun isHeld(url: String) = if (holdTheChapterPage) "/chapters/" in url else url.endsWith("/comments/2")
            val held = CompletableDeferred<Unit>()
            var gate: CompletableDeferred<Unit>? = held
            val session = Session(basic) { url -> if (url.endsWith("/comments/2")) page(li(1, 77, li(2))) else basic }
            session.getGate = { url -> gate.takeIf { isHeld(url) } }
            val viewModel = model(session, focused = 2L, position = 3)
            until("the held read") { session.urls.any(::isHeld) }

            viewModel.setScope(CommentScope.All)
            gate = null; held.complete(Unit)
            until("the work's page") { loaded(viewModel) && session.urls.last().let { !isHeld(it) && "/chapters/" !in it } }
            repeat(10) { idle(); Thread.sleep(10) }

            assertEquals(CommentScope.All, viewModel.scope.value)
            assertEquals(work, viewModel.currentTarget.value)
            assertEquals(null, viewModel.focusedCommentId.value)
            if (!holdTheChapterPage) assertEquals(true, session.urls.none { "/chapters/" in it })
        }
    }

    /** Pull to refresh: the page is read again, and stays on screen while it is. */
    @Test
    fun aPullToRefreshReadsThePageAgainWithoutEmptyingTheScreen() = runTest(testDispatcher) {
        val session = Session(basic)
        val viewModel = model(session)
        until("the first page") { loaded(viewModel) }
        val reads = session.urls.size

        val held = CompletableDeferred<Unit>()
        session.getGate = { held }
        val refresh = launch { viewModel.refresh() }
        until("the read to begin") { session.urls.size > reads }
        assertEquals("the page is still shown while AO3 answers", true, loaded(viewModel))
        session.getGate = { null }; held.complete(Unit)
        until("the refresh to end") { refresh.isCompleted }
        assertEquals(true, loaded(viewModel))
        assertEquals(reads + 1, session.urls.size)
    }

    /** The picker's empty sheet: while the list is asked for it is loading; a failure is said, and asking again clears it. */
    @Test
    fun aChapterListThatFailsSaysSoAndAskingAgainClearsIt() = runTest(testDispatcher) {
        var served: AO3Result<AO3HttpResponse> = AO3Result.Failure(io.github.cidy02.kudos.network.ao3.AO3Error.Network("offline"))
        var gate: CompletableDeferred<Unit>? = CompletableDeferred()
        val session = Session(basic) { url -> if ("/navigate" in url) served else basic }
        session.getGate = { url -> gate.takeIf { "/navigate" in url } }
        val chapters = AO3ChapterIndexRepository(PublicPage(basic), session)
        val viewModel = model(session)
        until("the first page") { loaded(viewModel) }

        viewModel.loadChaptersIfNeeded(chapters)
        until("asking") { viewModel.chaptersLoading.value }
        assertEquals(false, viewModel.chaptersFailed.value)
        gate!!.complete(Unit); gate = null
        until("the failure") { viewModel.chaptersFailed.value }
        assertEquals(io.github.cidy02.kudos.network.ao3.AO3Error.Network("offline").displayMessage(), viewModel.chaptersFailureMessage.value)
        assertEquals(false, viewModel.chaptersLoading.value)

        served = success("<ol class='chapter index group'><li><a href='/works/123/chapters/1001'>1. Chapter</a></li></ol>")
        val held = CompletableDeferred<Unit>().also { gate = it }
        viewModel.loadChaptersIfNeeded(chapters)
        until("asking again") { viewModel.chaptersLoading.value }
        assertEquals("asked again: the old failure is not shown beside the spinner", false, viewModel.chaptersFailed.value)
        assertEquals(null, viewModel.chaptersFailureMessage.value)
        gate = null; held.complete(Unit)
        until("the list") { viewModel.chapters.value.size == 1 }
        assertEquals(false, viewModel.chaptersLoading.value)
        assertEquals(false, viewModel.chaptersFailed.value)
    }

    /** A32-5. One session's chapter list is not the next one's, whatever the name. */
    @Test
    fun aChapterListIsReadAgainForANewSessionOfTheSameNameAndALateOneIsNotShown() = runTest(testDispatcher) {
        fun index(vararg numbers: Int) = success("<ol class='chapter index group'>" +
            numbers.joinToString("") { "<li><a href='/works/123/chapters/${1000 + it}'>$it. Chapter</a></li>" } + "</ol>")
        var served = index(1)
        var gate: CompletableDeferred<Unit>? = null
        val session = Session(basic) { url -> if ("/navigate" in url) served else basic }
        session.getGate = { url -> gate.takeIf { "/navigate" in url } }
        val chapters = AO3ChapterIndexRepository(PublicPage(index(1)), session)
        val viewModel = model(session)
        until("the first page") { loaded(viewModel) }
        viewModel.loadChaptersIfNeeded(chapters)
        until("the first session's list") { viewModel.chapters.value.size == 1 }

        // Signed out and in again as the same name. The first session's list goes at once, and is read again.
        session.generation = 2; served = index(1, 2)
        viewModel.loadChaptersIfNeeded(chapters)
        assertEquals(0, viewModel.chapters.value.size)
        until("the second session's list") { viewModel.chapters.value.size == 2 }

        // A list asked for in one session that answers in the next is not shown.
        val held = CompletableDeferred<Unit>().also { gate = it }
        session.generation = 3; served = index(1, 2, 3)
        viewModel.loadChaptersIfNeeded(chapters)
        until("the third session's read, held") { session.urls.count { "/navigate" in it } == 3 }
        session.generation = 4
        gate = null; held.complete(Unit)
        repeat(20) { idle(); Thread.sleep(10) }
        assertEquals(0, viewModel.chapters.value.size)
    }

    /** The reader's button names a chapter; a chapter the reader chose before its index answered stands. */
    @Test
    fun aChapterTheReaderChoseIsNotReplacedByTheOneTheReadersButtonAskedFor() = runTest(testDispatcher) {
        val viewModel = model(Session(basic))
        until("the first page") { loaded(viewModel) }
        viewModel.selectChapter(AO3ChapterRef(88L, 4, "Four"))
        viewModel.openOnChapter(AO3ChapterRef(77L, 3, "Three")) // the index, answering late
        until("a chapter's page") { loaded(viewModel) }
        assertEquals(AO3CommentTarget.Chapter(workId, 88L), viewModel.currentTarget.value)
        assertEquals(88L, viewModel.selectedChapter.value?.chapterId)
    }
}

/** A draft store whose reads ([gate]) and writes ([writeGate]) can be held after they have begun. */
private class GatedStore(private val inner: DataStore<Preferences>) : DataStore<Preferences> {
    var gate: CompletableDeferred<Unit>? = null
    var writeGate: CompletableDeferred<Unit>? = null
    override val data: Flow<Preferences> get() = flow { gate?.await(); emitAll(inner.data) }
    override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences {
        writeGate?.await()
        return inner.updateData(transform)
    }
}

private class PublicPage(private val result: AO3Result<AO3HttpResponse>) : AO3Client {
    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> = result
}

/** A signed-in session whose name and count a test can move, and whose reads and POST it can hold. */
private class Session(
    private val fallback: AO3Result<AO3HttpResponse>,
    private val page: ((String) -> AO3Result<AO3HttpResponse>)? = null
) : AO3AuthenticatedClient {
    var name: String? = "alice"
    var generation = 1
    val urls = mutableListOf<String>()
    val posts = mutableListOf<String>()
    var getGate: (String) -> CompletableDeferred<Unit>? = { null }
    var postGate: CompletableDeferred<Unit>? = null
    var postAnswer: AO3Result<AO3HttpResponse> = success("<div class='flash comment_notice'>Comment created!</div>")
    var getAnswer: AO3Result<AO3HttpResponse>? = null
    /** Becomes [getAnswer] once a POST is sent: what reads after it see. */
    var answerAfterPost: AO3Result<AO3HttpResponse>? = null

    override fun username(): String? = name
    override fun sessionGeneration(): Int? = generation
    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
        urls += url
        getGate(url)?.await()
        return getAnswer ?: page?.invoke(url) ?: fallback
    }
    override suspend fun postAuthenticated(
        url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        posts += url
        answerAfterPost?.let { getAnswer = it; answerAfterPost = null }
        postGate?.await()
        return postAnswer
    }
}
