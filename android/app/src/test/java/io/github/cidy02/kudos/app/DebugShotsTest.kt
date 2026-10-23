package io.github.cidy02.kudos.app

import java.io.File
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertEquals
import org.junit.Test

class DebugShotsTest {
    @Test
    fun speechAndAuthorBookmarksShotsOpenTheirProductionDestinations() {
        assertEquals(DebugShot(Routes.reader("reader-id"), listOf("reader")),
            debugShot("readerspeech", "queue-id", "collection-id", "work-id", "reader-id"))
        assertEquals(DebugShot(Routes.authorProfile("AO3_Reader", io.github.cidy02.kudos.author.AuthorTab.Bookmarks)),
            debugShot("authorbookmarks", "queue-id", "collection-id", "work-id", "reader-id"))
    }

    @Test
    fun everyA82NameIsKnownToTheDispatcher() {
        val inventory = generateSequence(File(System.getProperty("user.dir"))) { it.parentFile }
            .map { File(it, "docs/android-port/audits/A82-shots.md") }
            .first { it.isFile }
        val names = Regex("""^\| `([^`]+)` \|""", RegexOption.MULTILINE)
            .findAll(inventory.readText()).map { it.groupValues[1] }.toList()
        assertTrue("A82 must contain shot names", names.isNotEmpty())
        names.forEach { name ->
            assertNotNull("shot:$name", debugShot(name, "queue-id", "collection-id", "work-id", "reader-id"))
        }
    }
}
