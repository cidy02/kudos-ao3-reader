package io.github.cidy02.kudos.ui.subject

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertWidthIsEqualTo
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import io.github.cidy02.kudos.account.AO3CollectionCard
import io.github.cidy02.kudos.account.InboxItemCard
import io.github.cidy02.kudos.app.PrivacyGate
import io.github.cidy02.kudos.core.model.SavedWork
import io.github.cidy02.kudos.data.local.KudosDatabase
import io.github.cidy02.kudos.files.WorkFileStore
import io.github.cidy02.kudos.library.CollectionsScreen
import io.github.cidy02.kudos.library.LibraryRepository
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeKind
import io.github.cidy02.kudos.network.ao3.account.AO3Collection
import io.github.cidy02.kudos.network.ao3.comments.AO3CommentWorkAuthor
import io.github.cidy02.kudos.network.ao3.inbox.AO3InboxItem
import io.github.cidy02.kudos.ui.theme.KudosTheme
import io.github.cidy02.kudos.ui.theme.KudosThemeMode
import io.github.cidy02.kudos.works.WorkRepository
import java.nio.file.Files
import java.time.Instant
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
// Tall enough for all four preview tiles and the second collection in the lazy grid.
@Config(sdk = [34], application = Application::class, qualifiers = "w411dp-h2400dp")
// Real text measurement: the default stand-in does not wrap lines, so "does this text overflow"
// would be asked of a layout that never happens on a device.
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class LargeTextScreensTest {
    @get:Rule val compose = createComposeRule()
    private var database: KudosDatabase? = null
    private var filesRoot: java.io.File? = null

    @After
    fun tearDown() {
        database?.close()
        filesRoot?.deleteRecursively()
    }

    @Test
    fun inboxAtScaleTwoStacksIdentityStatusAndDateWithoutClipping() {
        val item = inboxItem(large = true)
        showInbox(2f, item)
        listOf(item.commenterName, "Author", "Replied", item.postedAgo,
            "on", "Chapter 12", "of ${item.workTitle}", item.excerpt).forEach(::assertReadable)
        assertBelow("Author", item.commenterName)
        assertBelow("Replied", "Author")
        assertBelow(item.postedAgo, "Replied")
        assertBelow("of ${item.workTitle}", "Chapter 12")
        assertTrue(layout(item.commenterName).lineCount > 1)
        assertTrue(layout("of ${item.workTitle}").lineCount > 2)
    }

    @Test
    fun inboxAtScaleOneKeepsItsBylineAndChapterRows() {
        val item = inboxItem(large = false)
        showInbox(1f, item)
        assertRow(item.commenterName, "Author", "Replied", item.postedAgo)
        assertRow("on", "Chapter 12", "of ${item.workTitle}")
    }

    @Test
    fun ao3CollectionAtScaleTwoStacksChipsAndDateAndWrapsTitleAndSummary() {
        val collection = ao3Collection(large = true)
        showAO3Collection(2f, collection)
        val kicker = maintainer.uppercase()
        listOf(kicker, "Unrevealed", "Anonymous", collection.title,
            "by ${collection.byline}", collection.summary, facts,
            collection.updatedAtText).forEach(::assertReadable)
        assertBelow("Unrevealed", kicker)
        assertBelow("Anonymous", "Unrevealed")
        assertBelow(collection.title, "Anonymous")
        assertBelow(collection.updatedAtText, facts)
        assertTrue(layout(collection.title).lineCount > 2)
        assertTrue(layout(collection.summary).lineCount > 2)
        assertTrue(layout(kicker).lineCount > 1)
    }

    @Test
    fun ao3CollectionAtScaleOneKeepsItsKickerChipAndStatsRows() {
        val collection = ao3Collection(large = false)
        showAO3Collection(1f, collection)
        assertRow("YOU OWN", "Unrevealed", "Anonymous")
        assertRow(facts, collection.updatedAtText)
        assertBelow(collection.title, "Anonymous")
        assertTrue(layout(collection.title).lineCount <= 2)
        assertTrue(layout(collection.summary).lineCount <= 2)
    }

    @Test
    fun localCollectionsAtScaleTwoStackAllFourTilesAndGrowWithTheirText() {
        val works = previewWorks(large = true)
        val name = "A collection of stories with a long name that must remain readable in full"
        showLocalCollections(2f, name, works)
        (listOf(name, "4 works", secondCollection) + works.flatMap { listOf(it.title, it.author) })
            .forEach(::assertReadable)
        works.forEach { assertBelow(it.author, it.title) }
        works.zipWithNext().forEach { (first, next) -> assertBelow(next.title, first.author) }
        assertBelow(secondCollection, name)
        assertTrue(layout(name).lineCount > 2)
        works.forEach {
            assertTrue(layout(it.title).lineCount > 2)
            assertTrue(layout(it.author).lineCount > 1)
        }
    }

    @Test
    fun localCollectionsAtScaleOneKeepTheTwoByTwoMosaicAndTwoCardGrid() {
        val works = previewWorks(large = false)
        val name = "Weekend"
        showLocalCollections(1f, name, works)
        assertRow(works[0].title, works[1].title)
        assertRow(works[2].title, works[3].title)
        assertBelow(works[2].title, works[0].author)
        assertRow(name, secondCollection)
        compose.onNodeWithContentDescription("$name, 4 works. Opens collection.")
            .assertWidthIsEqualTo(SubjectWorkCardMetrics.width)
    }

    private fun show(scale: Float, content: @Composable () -> Unit) {
        compose.setContent {
            val density = LocalDensity.current
            CompositionLocalProvider(LocalDensity provides Density(density.density, scale)) {
                KudosTheme(KudosThemeMode.Light, content = content)
            }
        }
        compose.onRoot().assertWidthIsEqualTo(411.dp)
    }

    // Render the actual Inbox row in its page's lazy-list width, with no repository/client.
    private fun showInbox(scale: Float, item: AO3InboxItem) = show(scale) {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = SubjectMetrics.accountGutter)
        ) {
            item {
                InboxItemCard(
                    item = item, workAuthors = listOf(AO3CommentWorkAuthor(item.commenterName)),
                    currentUsername = null, isSelecting = false, isSelected = false,
                    isSelectable = false, isFirst = true, isLast = true,
                    isPerformingAction = false, canMarkRead = false, canMarkUnread = false,
                    canDelete = false, onOpen = {}, onToggleSelection = {}, onMarkRead = {},
                    onMarkUnread = {}, onDelete = {}
                )
            }
        }
    }

    private fun showAO3Collection(scale: Float, collection: AO3Collection) = show(scale) {
        LazyColumn(Modifier.fillMaxSize()) {
            item {
                AO3CollectionCard(
                    collection = collection, onClick = {}, palette = LocalSubjectPalette.current,
                    modifier = Modifier.padding(horizontal = SubjectMetrics.headerGutter)
                )
            }
        }
    }

    // The full local page uses real in-memory Room repositories: this also pins its grid columns.
    private fun showLocalCollections(scale: Float, name: String, works: List<SavedWork>) {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val db = Room.inMemoryDatabaseBuilder(context, KudosDatabase::class.java)
            .allowMainThreadQueries().build()
        database = db
        val root = Files.createTempDirectory("kudos-large-text")
        filesRoot = root.toFile()
        var clockTick = 0L
        val repository = WorkRepository(db, WorkFileStore(root), clock = { Instant.EPOCH.plusSeconds(clockTick++) })
        runBlocking {
            works.forEach { repository.upsert(it) }
            repository.createCollection(secondCollection)
            val collection = repository.createCollection(name)
            works.forEach { repository.addWorkToCollection(it.id, collection.id) }
        }
        val libraryRepository = LibraryRepository(repository)
        val privacyGate = PrivacyGate()
        show(scale) {
            CollectionsScreen(repository, libraryRepository, privacyGate, onOpenCollection = {})
        }
        compose.waitUntil(5_000) {
            compose.onAllNodesWithText(name, useUnmergedTree = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun assertReadable(text: String) {
        val interaction = compose.onNodeWithText(text, useUnmergedTree = true).assertIsDisplayed()
        val node = interaction.fetchSemanticsNode()
        // Use position + measured size, not only the already-clipped semantics bounds.
        val position = node.positionInRoot
        val bounds = Rect(position.x, position.y,
            position.x + node.size.width, position.y + node.size.height)
        val parent = requireNotNull(node.parent)
        assertContains("$text: semantics parent", parent.boundsInRoot, bounds)
        assertContains("$text: visible bounds", node.boundsInRoot, bounds)
        // Layout parents include the actual tile/Row/Column even when they have no semantics.
        var coordinates = node.layoutInfo.coordinates.parentLayoutCoordinates
        while (coordinates != null) {
            val origin = coordinates.positionInRoot()
            val parentBounds = Rect(origin.x, origin.y,
                origin.x + coordinates.size.width, origin.y + coordinates.size.height)
            assertContains("$text: layout parent", parentBounds, bounds)
            coordinates = coordinates.parentLayoutCoordinates
        }
        val result = layout(text)
        // Not `hasVisualOverflow`: a short label sized to its text reports a paragraph as wide as
        // its constraint and a size as wide as its glyphs, which reads as overflow and is not.
        // What cuts text is a height it does not fit, a line limit it exceeds, or an ellipsis.
        assertFalse("$text: cut off in height", result.didOverflowHeight)
        assertFalse("$text: more lines than allowed", result.multiParagraph.didExceedMaxLines)
        for (line in 0 until result.lineCount) {
            assertFalse("$text: ellipsized line $line", result.isLineEllipsized(line))
        }
    }

    private fun assertContains(message: String, parent: Rect, child: Rect) {
        val tolerance = 1f // Pixel rounding at independently measured edges.
        assertTrue("$message: $child outside $parent",
            child.left >= parent.left - tolerance && child.top >= parent.top - tolerance &&
                child.right <= parent.right + tolerance && child.bottom <= parent.bottom + tolerance)
    }

    private fun layout(text: String): TextLayoutResult {
        val results = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { action ->
                assertTrue(action(results))
            }
        return results.single()
    }

    private fun bounds(text: String): Rect = compose.onNodeWithText(text, useUnmergedTree = true)
        .assertIsDisplayed().fetchSemanticsNode().boundsInRoot

    private fun assertBelow(lower: String, upper: String) {
        assertTrue("$lower should be below $upper", bounds(lower).top >= bounds(upper).bottom - 1f)
    }

    private fun assertRow(vararg texts: String) {
        texts.toList().zipWithNext().forEach { (left, right) ->
            val a = bounds(left)
            val b = bounds(right)
            assertTrue("$left and $right should share a row",
                a.right <= b.left + 1f && a.top < b.bottom && b.top < a.bottom)
        }
    }

    private fun inboxItem(large: Boolean) = AO3InboxItem(
        id = 1L,
        commenterName = if (large) "A commenter with a very long display name that must wrap completely" else "Ada",
        subjectTitle = "Chapter 12 of " + if (large) longTitle else "Story",
        workId = 42L, excerpt = "Thank you for sharing this story.",
        postedAgo = if (large) "Wednesday, September 30, 2026 at 11:45 in the evening" else "1d ago",
        isUnread = true, isReplied = true, canReply = false
    )

    private fun ao3Collection(large: Boolean) = AO3Collection(
        name = "fixture", title = if (large) longTitle else "Stories",
        summary = if (large) "A collection summary with enough words to span several lines at the largest text size. " +
            "Every sentence should remain visible, including this final sentence at the end." else "A few stories.",
        byline = if (large) "Several maintainers with long display names collaborating on these stories" else "Ada",
        maintainerNames = if (large) listOf(maintainer) else emptyList(),
        viewerIsOwner = !large, isUnrevealed = true, isAnonymous = true, isModerated = true,
        isClosed = true, worksCount = 12345, bookmarksCount = 6789,
        challengeKind = AO3ChallengeKind.GiftExchange,
        updatedAtText = if (large) "Updated Wednesday, September 30, 2026" else "30 Sep 2026"
    )

    private fun previewWorks(large: Boolean) = (1..4).map { index ->
        SavedWork(
            id = "00000000-0000-4000-8000-00000000000$index",
            title = if (large) "Work $index: $longTitle" else "Work $index",
            author = if (large) "Author $index with a long display name and several coauthors whose names must wrap onto additional lines" else "Writer $index",
            dateAdded = Instant.EPOCH.minusSeconds(index.toLong()),
            isSaved = true
        )
    }

    private val longTitle = "A long title about finding the way home through the stars and all the stories we tell along the journey"
    private val facts = "12345 works · 6789 bookmarks · Moderated · Closed · Gift Exchange"
    private val maintainer = "A maintainer with a long name that must wrap instead of disappearing"
    private val secondCollection = "Second"
}
