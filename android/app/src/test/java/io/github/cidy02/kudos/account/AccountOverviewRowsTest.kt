package io.github.cidy02.kudos.account

import android.app.Application
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.lifecycle.ViewModelStore
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.app.PrivacyRevealState
import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.MemoryCookieStore
import io.github.cidy02.kudos.auth.MemorySessionStore
import io.github.cidy02.kudos.auth.testSession
import io.github.cidy02.kudos.core.model.MatureContentMode
import io.github.cidy02.kudos.core.model.PrivacySettings
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3HttpResponse
import io.github.cidy02.kudos.network.ao3.AO3PageCache
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorHeader
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRepository
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorWebAction
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxItem
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxRepository
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.writes.AO3AuthenticatedClient
import io.github.cidy02.kudos.ui.subject.LocalSubjectPalette
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.io.File
import java.nio.file.Files
import java.util.concurrent.CopyOnWriteArrayList
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class AccountOverviewRowsTest {
    @get:Rule(order = -2) val closesLast = object : org.junit.rules.ExternalResource() {
        override fun after() {
            if (::database.isInitialized) database.close()
            dir.toFile().deleteRecursively()
        }
    }
    @get:Rule val compose = createComposeRule()

    private val dir = Files.createTempDirectory("account-a470")
    private val models = ViewModelStore()
    private lateinit var database: KudosDatabase
    private lateinit var works: WorkRepository

    @Before
    fun setUp() {
        AO3PageCache.shared.clear()
        val app = ApplicationProvider.getApplicationContext<Application>()
        database = Room.inMemoryDatabaseBuilder(app, KudosDatabase::class.java)
            .allowMainThreadQueries()
            .build()
        works = WorkRepository(database, WorkFileStore(dir))
    }

    @After
    fun tearDown() {
        compose.runOnIdle { models.clear() }
    }

    private fun top(text: String): Float =
        compose.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.top

    private fun left(text: String): Float =
        compose.onNodeWithText(text, useUnmergedTree = true).fetchSemanticsNode().boundsInRoot.left

    private fun work(
        id: Long,
        title: String,
        rating: String = "General Audiences",
        chapters: String = "3/5"
    ) = AO3WorkSummary(
        id = id,
        title = title,
        authors = listOf("Avery_Archive"),
        fandoms = listOf("Star Wars"),
        rating = rating,
        warnings = emptyList(),
        categories = emptyList(),
        chapters = chapters,
        wordCount = 4_200,
        kudos = 18
    )

    private fun header(
        username: String = "Avery_Archive",
        recentWorks: List<AO3WorkSummary>? = listOf(work(101L, "Newest Chapter Story"))
    ) = AO3AuthorHeader(
        username = username,
        displayName = username,
        avatarUrl = null,
        userId = null,
        pseuds = emptyList(),
        fandoms = emptyList(),
        subscriptionForm = null,
        actions = listOf(
            AO3AuthorWebAction("Works (12)", "https://archiveofourown.org/users/$username/works", AO3AuthorWebAction.Kind.Works),
            AO3AuthorWebAction("Series (3)", "https://archiveofourown.org/users/$username/series", AO3AuthorWebAction.Kind.Other),
            AO3AuthorWebAction("Bookmarks (5)", "https://archiveofourown.org/users/$username/bookmarks", AO3AuthorWebAction.Kind.Other)
        ),
        recentWorks = recentWorks,
        recentSeries = emptyList(),
        recentBookmarks = emptyList()
    )

    private fun inboxItem(
        id: Long,
        commenter: String,
        subject: String,
        workId: Long?,
        excerpt: String,
        unread: Boolean = true
    ) = AO3InboxItem(
        id = id,
        commenterName = commenter,
        commenterUsername = commenter.lowercase(),
        subjectTitle = subject,
        subjectUrl = workId?.let { "https://archiveofourown.org/works/$it/comments/$id" },
        workId = workId,
        excerpt = excerpt,
        postedAgo = "2 hours ago",
        isUnread = unread,
        isReplied = false,
        canReply = true
    )

    @Test
    fun readingOverviewOmitsMarkedForLaterAndSaysPage() {
        assertEquals(
            listOf("Bookmarks", "Collections", "Subscriptions"),
            accountOverviewReadingRows().map { it.title }
        )
        assertFalse(accountOverviewReadingRows().any { it.title == "Marked for Later" })
        assertEquals(
            "When you sign in, this page shows your AO3 account and activity.",
            SIGNED_OUT_ACCOUNT_LINE
        )
    }

    @Test
    fun signedInAccountSheetFollowsIosSectionOrderAndHeaderActions() {
        val auth = AO3AuthRepository(MemorySessionStore(testSession("Avery_Archive")), MemoryCookieStore())
        runBlocking { auth.restoreSession() }
        val transport = AccountFakeTransport(auth)
        val authorRepo = AO3AuthorRepository(transport, transport, parseDispatcher = Dispatchers.Unconfined)
        val inboxRepo = AO3InboxRepository(transport)
        val countsCache = AO3AccountListCountsCache()
        countsCache.put(
            AccountListType.Subscriptions,
            AO3AccountListCountsCache.scope("Avery_Archive", auth.generation.value),
            AO3AccountListCountsCache.Count(exact = 9)
        )
        val vm = AccountViewModel(auth, authorRepo, countsCache, inboxRepo)
        models.put("signed-in-order", vm)
        val openedWeb = mutableListOf<String>()
        var dashboardClicks = 0
        var inboxClicks = 0
        var settingsClicks = 0
        var backupClicks = 0
        var aboutClicks = 0

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AccountScreen(
                    authRepository = auth,
                    workRepository = works,
                    onLogin = {},
                    onOpenList = {},
                    onOpenDashboard = { dashboardClicks++ },
                    onOpenWeb = { openedWeb += it },
                    onOpenInbox = { inboxClicks++ },
                    onOpenSettings = { settingsClicks++ },
                    onOpenBackup = { backupClicks++ },
                    onOpenAbout = { aboutClicks++ },
                    authorRepository = authorRepo,
                    countsCache = countsCache,
                    inboxRepository = inboxRepo,
                    privacySettings = PrivacySettings(hideMatureContent = false),
                    viewModel = vm
                )
            }
        }

        compose.waitUntil(15_000) {
            compose.onAllNodesWithText("YOUR LATEST", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty() &&
                compose.onAllNodesWithText("First inbox preview message", useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
        compose.waitForIdle()

        // Signed-in open fetches only dashboard, profile about, and inbox page 1 (no extra enrichment).
        assertEquals(
            setOf(
                "https://archiveofourown.org/users/Avery_Archive", // route.dashboardUrl: AO3's dashboard is /users/<name>
                "https://archiveofourown.org/users/Avery_Archive/profile",
                "https://archiveofourown.org/users/Avery_Archive/inbox"
            ),
            transport.gets.toSet()
        )
        assertEquals(3, transport.gets.size)

        // Header action buttons: View Profile, Share, Edit left-to-right.
        assertTrue(left("View Profile") < left("Share"))
        assertTrue(left("Share") < left("Edit"))
        compose.onNodeWithText("View Profile").performClick()
        compose.onNodeWithText("Edit").performClick()
        assertEquals(
            listOf(
                "native:profile",
                "https://archiveofourown.org/users/Avery_Archive/profile/edit"
            ),
            openedWeb
        )

        // Vertical section order: Header -> Actions -> Count Strip -> Your Latest -> Inbox Card -> AO3 -> Kudos -> Log Out.
        val headerTop = top("Avery_Archive")
        val actionsTop = top("View Profile")
        val stripTop = top("Works")
        val latestTop = top("YOUR LATEST")
        val inboxCardTop = compose.onNodeWithTag("Account Inbox Card Header").fetchSemanticsNode().boundsInRoot.top
        val ao3GroupTop = top("AO3")
        val kudosGroupTop = top("KUDOS")
        val logOutTop = top("Log Out")

        val sectionTops = listOf(
            headerTop,
            actionsTop,
            stripTop,
            latestTop,
            inboxCardTop,
            ao3GroupTop,
            kudosGroupTop,
            logOutTop
        )
        assertEquals("Sections must appear in iOS T-470 vertical order", sectionTops.sorted(), sectionTops)
        assertTrue(headerTop < actionsTop)
        assertTrue(actionsTop < stripTop)
        assertTrue(stripTop < latestTop)
        assertTrue(latestTop < inboxCardTop)
        assertTrue(inboxCardTop < ao3GroupTop)
        assertTrue(ao3GroupTop < kudosGroupTop)
        assertTrue(kudosGroupTop < logOutTop)

        // AO3 group rows and Kudos group rows.
        compose.onNodeWithText("AO3 Preferences").performClick()
        compose.onNodeWithText("My Dashboard").performClick()
        compose.onNodeWithText("More on AO3").performClick()
        compose.onNodeWithText("Open AO3").performClick()
        compose.onNodeWithText("Settings").performClick()
        compose.onNodeWithText("Backup & Sync").performClick()
        compose.onNodeWithText("About").performClick()
        assertEquals(1, dashboardClicks)
        assertEquals(1, settingsClicks)
        assertEquals(1, backupClicks)
        assertEquals(1, aboutClicks)
        assertTrue(openedWeb.containsAll(listOf("native:preferences", "native:more-on-ao3", "https://archiveofourown.org")))
    }

    @Test
    fun countStripLinksToWorksSeriesBookmarksAndSubscriptions() {
        val openedLists = mutableListOf<AccountListType>()
        val openedSeries = mutableListOf<String>()
        val activeRoute = AO3AuthorRoute("Avery_Archive")
        val h = header("Avery_Archive")
        val counts = mapOf(
            AccountListType.Subscriptions.listKey to AO3AccountListCountsCache.Count(exact = 9)
        )

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AccountProfileCountStrip(
                    header = h,
                    route = activeRoute,
                    counts = counts,
                    onOpenList = { openedLists += it },
                    onOpenSeries = { openedSeries += it }
                )
            }
        }
        compose.waitForIdle()

        assertTrue(left("Works") < left("Series"))
        assertTrue(left("Series") < left("Bookmarks"))
        assertTrue(left("Bookmarks") < left("Subscriptions"))

        compose.onNodeWithContentDescription("12 works").performClick()
        compose.onNodeWithContentDescription("3 series").performClick()
        compose.onNodeWithContentDescription("5 bookmarks").performClick()
        compose.onNodeWithContentDescription("9 subscriptions").performClick()

        assertEquals(
            listOf(AccountListType.MyWorks, AccountListType.Bookmarks, AccountListType.Subscriptions),
            openedLists
        )
        assertEquals(
            listOf("https://archiveofourown.org/users/Avery_Archive/series"),
            openedSeries
        )
    }

    @Test
    fun signedOutAccountShowsInviteRequestTextLineUnderLogInAndOpensInvitePage() {
        val auth = AO3AuthRepository(MemorySessionStore(null), MemoryCookieStore())
        runBlocking { auth.restoreSession() }
        val transport = AccountFakeTransport(auth)
        val authorRepo = AO3AuthorRepository(transport, transport, parseDispatcher = Dispatchers.Unconfined)
        val inboxRepo = AO3InboxRepository(transport)
        val vm = AccountViewModel(auth, authorRepo, null, inboxRepo)
        models.put("signed-out", vm)
        val openedWeb = mutableListOf<String>()
        var loginTaps = 0

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AccountScreen(
                    authRepository = auth,
                    workRepository = works,
                    onLogin = { loginTaps++ },
                    onOpenList = {},
                    onOpenWeb = { openedWeb += it },
                    authorRepository = authorRepo,
                    inboxRepository = inboxRepo,
                    viewModel = vm
                )
            }
        }
        compose.waitForIdle()

        assertTrue("Signed-out Account sheet must make no AO3 requests", transport.gets.isEmpty())
        compose.onNodeWithText("Bring your AO3 account along").assertExists()
        compose.onNodeWithText("YOUR LATEST").assertDoesNotExist()
        compose.onNodeWithText("AO3").assertDoesNotExist()
        compose.onNodeWithText("Log Out").assertDoesNotExist()
        compose.onNodeWithText("KUDOS").assertExists()
        compose.onNodeWithText("Settings").assertExists()

        val loginNode = compose.onNodeWithText("Log In to AO3")
        val inviteNode = compose.onNodeWithText("No AO3 account? Create one")
        assertTrue(
            "\"No AO3 account? Create one\" must sit under \"Log In to AO3\"",
            loginNode.fetchSemanticsNode().boundsInRoot.top < inviteNode.fetchSemanticsNode().boundsInRoot.top
        )
        assertFalse(
            "\"No AO3 account? Create one\" must be a text line, not a Button",
            inviteNode.fetchSemanticsNode().config.contains(SemanticsProperties.Role)
        )
        inviteNode.assertHasClickAction().performClick()
        assertEquals(listOf("https://archiveofourown.org/invite_requests"), openedWeb)
        loginNode.performClick()
        assertEquals(1, loginTaps)
    }

    @Test
    fun inboxCardShowsAtMostTwoMessagesAndOpensItemOrFullInbox() {
        val items = listOf(
            inboxItem(501L, "ReaderOne", "Chapter 2 of Dawn", 101L, "First inbox preview message"),
            inboxItem(502L, "ReaderTwo", "Starlight", 102L, "Second inbox preview message"),
            inboxItem(503L, "ReaderThree", "Epilogue", 103L, "Third inbox preview message that must not appear")
        )
        val openedComments = mutableListOf<Pair<Long, Long?>>()
        var inboxOpened = 0

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AccountInboxSection(
                    inboxPreview = AccountInboxPreviewState.Loaded(items = items, unreadCount = 2),
                    unreadCount = 2,
                    palette = LocalSubjectPalette.current,
                    onOpenInbox = { inboxOpened++ },
                    onOpenWorkComments = { workId, commentId -> openedComments += workId to commentId },
                    onOpenWeb = {},
                    onRetry = {}
                )
            }
        }
        compose.waitForIdle()

        compose.onNodeWithText("First inbox preview message").assertExists()
        compose.onNodeWithText("Second inbox preview message").assertExists()
        compose.onNodeWithText("Third inbox preview message that must not appear").assertDoesNotExist()

        compose.onNodeWithText("First inbox preview message").performClick()
        assertEquals(listOf(101L to 501L), openedComments)

        compose.onNodeWithTag("Account Inbox Card Header").performClick()
        assertEquals(1, inboxOpened)
    }

    @Test
    fun yourLatestRespectsPrivacy_hidingExplicitObscuringWithoutExposingTitleToTalkBackAndShowingSafe() {
        val concealedLabel = "Hidden mature work. Activate to reveal."
        val explicitWork = work(1L, "Hidden Explicit Title", rating = "Explicit")
        val safeWork = work(2L, "Safe Visible Title", rating = "General Audiences")
        val openedWorks = mutableListOf<AO3WorkSummary>()
        val revealState = PrivacyRevealState()
        val privacyState = androidx.compose.runtime.mutableStateOf(
            PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Hide)
        )
        val loadedState = androidx.compose.runtime.mutableStateOf(true)
        val headerState = androidx.compose.runtime.mutableStateOf(header(recentWorks = listOf(explicitWork)))

        compose.setContent {
            KudosTheme(KudosThemeMode.Light) {
                AccountLatestSection(
                    header = headerState.value,
                    env = null,
                    privacyLoaded = loadedState.value,
                    privacy = privacyState.value,
                    reveal = revealState,
                    onOpenWork = { openedWorks += it }
                )
            }
        }
        compose.waitForIdle()

        // 1. Hide mode omits Your Latest completely.
        compose.onAllNodesWithText("YOUR LATEST", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Hidden Explicit Title", useUnmergedTree = true).assertCountEquals(0)

        // 2. Unread settings (privacyLoaded = false) fail closed even if privacy says hideMatureContent = false.
        compose.runOnIdle {
            loadedState.value = false
            privacyState.value = PrivacySettings(hideMatureContent = false)
        }
        compose.waitForIdle()
        compose.onAllNodesWithText("YOUR LATEST", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithText("Hidden Explicit Title", useUnmergedTree = true).assertCountEquals(0)

        // 3. Obscure mode blurs the card and redacts/conceals the title from TalkBack until revealed.
        compose.runOnIdle {
            loadedState.value = true
            privacyState.value = PrivacySettings(hideMatureContent = true, matureContentMode = MatureContentMode.Obscure)
        }
        compose.waitForIdle()
        compose.onAllNodesWithText("YOUR LATEST", useUnmergedTree = true).assertCountEquals(1)
        compose.onAllNodesWithText("Hidden Explicit Title", useUnmergedTree = true).assertCountEquals(0)
        compose.onAllNodesWithContentDescription(concealedLabel, useUnmergedTree = true).assertCountEquals(1)

        // Tapping the concealed card reveals it without navigating yet; tapping again opens the work.
        compose.onNodeWithContentDescription(concealedLabel).performClick()
        compose.waitForIdle()
        assertTrue("Reveal tap must not open the work before it is visible", openedWorks.isEmpty())
        compose.onAllNodesWithText("Hidden Explicit Title", useUnmergedTree = true).assertCountEquals(1)
        compose.onNodeWithText("Hidden Explicit Title").performClick()
        assertEquals(listOf(explicitWork), openedWorks)

        // 4. Safe work renders visibly and opens on tap.
        compose.runOnIdle {
            openedWorks.clear()
            headerState.value = header(recentWorks = listOf(safeWork))
        }
        compose.waitForIdle()
        compose.onAllNodesWithText("Safe Visible Title", useUnmergedTree = true).assertCountEquals(1)
        compose.onNodeWithText("Safe Visible Title").performClick()
        assertEquals(listOf(safeWork), openedWorks)
    }
}

private class AccountFakeTransport(
    private val auth: AO3AuthRepository
) : AO3Client, AO3AuthenticatedClient {
    val gets = CopyOnWriteArrayList<String>()

    override val sessionChanges get() = auth.generation
    override fun username(): String? = auth.username()
    override fun sessionGeneration(): Int = auth.generation.value

    override suspend fun get(url: String, headers: Map<String, String>): AO3Result<AO3HttpResponse> {
        gets += url
        val html = when {
            url.endsWith("/profile") -> fixtureHtml("ao3_author_profile")
            url.contains("/inbox") -> INBOX_HTML
            else -> fixtureHtml("ao3_author_dashboard_demo")
        }
        return AO3Result.Success(AO3HttpResponse(url, 200, emptyMap(), html))
    }

    override suspend fun getAuthenticated(url: String): AO3Result<AO3HttpResponse> = get(url, emptyMap())

    override suspend fun postAuthenticated(
        url: String,
        formFields: List<Pair<String, String>>,
        headers: Map<String, String>
    ): AO3Result<AO3HttpResponse> = AO3Result.Failure(AO3Error.Network("No writes in AccountOverviewRowsTest"))

    companion object {
        private const val INBOX_HTML = """
            <html><body><div id="main" class="inbox-show dashboard">
              <h2 class="heading">My Inbox (3 comments, 2 unread)</h2>
              <form id="inbox-form" action="/users/Avery_Archive/inbox" method="post">
                <input type="hidden" name="authenticity_token" value="token-1" />
                <ol class="comment index group">
                  <li class="unread comment group" id="feedback_comment_501">
                    <h4 class="heading byline">
                      <a href="/users/reader1/pseuds/reader1">ReaderOne</a> on
                      <a href="/works/101/comments/501">Chapter 2 of Two Voices at Dawn</a>
                      <span class="posted datetime">2 hours ago</span>
                    </h4>
                    <blockquote class="userstuff"><p>First inbox preview message</p></blockquote>
                    <ul class="actions">
                      <li><span class="unread">Unread</span></li>
                      <li><a href="/inbox/reply?comment_id=501">Reply</a></li>
                      <li><input type="checkbox" name="comments[]" value="901" /></li>
                    </ul>
                  </li>
                  <li class="unread comment group" id="feedback_comment_502">
                    <h4 class="heading byline">
                      <a href="/users/reader2/pseuds/reader2">ReaderTwo</a> on
                      <a href="/works/102/comments/502">Starlight</a>
                      <span class="posted datetime">5 hours ago</span>
                    </h4>
                    <blockquote class="userstuff"><p>Second inbox preview message</p></blockquote>
                    <ul class="actions">
                      <li><span class="unread">Unread</span></li>
                      <li><a href="/inbox/reply?comment_id=502">Reply</a></li>
                      <li><input type="checkbox" name="comments[]" value="902" /></li>
                    </ul>
                  </li>
                  <li class="read comment group" id="feedback_comment_503">
                    <h4 class="heading byline">
                      <a href="/users/reader3/pseuds/reader3">ReaderThree</a> on
                      <a href="/works/103/comments/503">Epilogue</a>
                      <span class="posted datetime">1 day ago</span>
                    </h4>
                    <blockquote class="userstuff"><p>Third inbox preview message</p></blockquote>
                    <ul class="actions">
                      <li><input type="checkbox" name="comments[]" value="903" /></li>
                    </ul>
                  </li>
                </ol>
              </form>
            </div></body></html>
        """

        private fun fixtureHtml(name: String): String {
            val file = listOf("src/debug/assets", "app/src/debug/assets", "android/app/src/debug/assets")
                .map { File("$it/fixtures/$name.html") }
                .firstOrNull(File::isFile)
                ?: error("Missing fixture: $name")
            return org.jsoup.Jsoup.parse(file.readText()).apply { select("img").remove() }.outerHtml()
        }
    }
}

