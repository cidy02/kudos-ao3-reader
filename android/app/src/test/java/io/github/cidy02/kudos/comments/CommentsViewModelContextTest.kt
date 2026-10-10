package io.github.cidy02.kudos.comments

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

    private val models = mutableListOf<CommentsViewModel>()
    private fun model(session: Session, focused: Long? = null, position: Int? = null) = CommentsViewModel(
        AO3CommentRepository(publicClient = PublicPage(basic), authenticatedClient = session),
        work, drafts, focused, position, { session.generation }) { session.name }.also { models += it }

    private fun loaded(viewModel: CommentsViewModel) = viewModel.state.value is CommentsUiState.Loaded

    private fun reply(id: Long) = AO3Comment(
        id = "comment_$id", author = AO3CommentAuthor(name = "Someone"), date = "2026-08-03", body = "Stub", canReply = true)

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
        success("<html><body class=\"logged-in\"><ol class=\"thread\">" + roots.joinToString("") + "</ol></body></html>")

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

/** A draft store whose reads can be held after they have begun. Writes are not held. */
private class GatedStore(private val inner: DataStore<Preferences>) : DataStore<Preferences> {
    var gate: CompletableDeferred<Unit>? = null
    override val data: Flow<Preferences> get() = flow { gate?.await(); emitAll(inner.data) }
    override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences) = inner.updateData(transform)
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

    override fun username(): String? = name
    override fun sessionGeneration(): Int? = generation
    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> {
        urls += url
        getGate(url)?.await()
        return page?.invoke(url) ?: fallback
    }
    override suspend fun postAuthenticated(
        url: String, formFields: List<Pair<String, String>>, headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> {
        posts += url
        postGate?.await()
        return success("<div class=\"flash comment_notice\">Comment created!</div>")
    }
}
