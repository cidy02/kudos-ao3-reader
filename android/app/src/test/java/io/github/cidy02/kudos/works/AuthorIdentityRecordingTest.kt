package io.github.cidy02.kudos.works

import io.github.cidy02.kudos.library.ReadingAffinities
import io.github.cidy02.kudos.network.ao3.author.AO3AuthorIdentities
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadata
import io.github.cidy02.kudos.network.ao3.work.AO3WorkMetadataParser
import java.time.Instant
import org.jsoup.Jsoup
import org.junit.Assert.assertEquals
import org.junit.Test

/** A byline's words are a pseud. Which AO3 account wrote a work is read from the link and kept. */
class AuthorIdentityRecordingTest {
    private val pseudLink = """<a rel="author" href="/users/SecondAccount/pseuds/Second%20Pseud">Second Pseud (SecondAccount)</a>"""
    private fun links(html: String) = Jsoup.parseBodyFragment(html).select("a[rel=author]")
    private val merger = WorkMetadataMerger()
    private val blurb = AO3WorkSummary(
        id = 1, title = "T", authors = listOf("Second Pseud (SecondAccount)"), fandoms = emptyList(),
        rating = "", warnings = emptyList(), categories = emptyList(),
        authorIdentitiesJSON = AO3AuthorIdentities.json(links(pseudLink))
    )

    @Test fun theAccountComesFromTheLinkNotFromTheBylinesWords() {
        assertEquals(
            """[{"username":"SecondAccount","pseud":"Second Pseud","displayName":"Second Pseud (SecondAccount)","kind":"registered"}]""",
            blurb.authorIdentitiesJSON
        )
    }

    /** The page a tapped name opens: the link's account, whatever words the link shows. */
    @Test fun aTappedNameOpensItsAccountNotAnAccountOfThatName() {
        val json = AO3AuthorIdentities.json(links(
            """<a rel="author" href="/users/Avery_Archive/pseuds/Avery%20Writes">Avery Writes</a>,
               $pseudLink, <a rel="author" href="/users/Solo/pseuds/Solo">Solo</a>"""
        ))
        fun route(name: String) = AO3AuthorIdentities.byline(json, name)
            ?.let { io.github.cidy02.kudos.network.ao3.author.AO3AuthorRoute.fromByline(it) }
        assertEquals("Avery_Archive" to "Avery Writes", route("Avery Writes")?.let { it.username to it.pseud })
        assertEquals("SecondAccount" to "Second Pseud", route("Second Pseud (SecondAccount)")?.let { it.username to it.pseud })
        assertEquals("Solo" to null, route("Solo")?.let { it.username to it.pseud })
        assertEquals(null, route("Somebody Else"))
        assertEquals(null, AO3AuthorIdentities.byline("", "Avery Writes"))
        assertEquals(null, AO3AuthorIdentities.byline("not json", "Avery Writes"))
        // Two accounts printed alike: no link, rather than always the first one's (A49 F9).
        val twins = AO3AuthorIdentities.json(links(
            """<a rel="author" href="/users/FirstAccount/pseuds/Alex">Alex</a>,
               <a rel="author" href="/users/SecondAccount/pseuds/Alex">Alex</a>"""
        ))
        assertEquals(null, AO3AuthorIdentities.byline(twins, "Alex"))
    }

    @Test fun anonymousNamesNoAccountAndAnOrphanedWorkNamesNoneToCheck() {
        assertEquals("", AO3AuthorIdentities.json(links("by Anonymous")))
        val orphaned = AO3AuthorIdentities.json(links("""<a rel="author" href="/users/orphan_account/pseuds/x">x (orphan_account)</a>"""))
        assertEquals("""[{"username":"orphan_account","pseud":"x","displayName":"x (orphan_account)","kind":"orphaned"}]""", orphaned)
    }

    @Test fun aWorkPageGivesTheWorksOwnBylineNotAChapters() {
        val page = AO3WorkMetadataParser().parse(
            """<h3 class="byline heading">$pseudLink</h3>
               <h3 class="byline heading">Chapter by <a rel="author" href="/users/Guest">Guest</a></h3>"""
        )
        assertEquals(blurb.authorIdentitiesJSON, page.authorIdentitiesJSON)
    }

    @Test fun theFavoriteAuthorsRowLearnsItsAccountFromWhatWasRecorded() {
        val saved = merger.merge(blurb, null, null, markSaved = true).copy(lastReadDate = Instant.EPOCH)
        assertEquals("SecondAccount", ReadingAffinities.authors(listOf(saved), emptyMap()).single().username)
    }

    @Test fun aBylineThatChangedWithoutNamingAnAccountForgetsTheOldOne() {
        val known = merger.merge(blurb, null, null, markSaved = true)
        val silent = blurb.copy(authorIdentitiesJSON = "")
        assertEquals("the same byline keeps it", known.authorIdentitiesJSON,
            merger.merge(silent, null, known, markSaved = false).authorIdentitiesJSON)
        assertEquals("a new byline without one drops it", "",
            merger.merge(silent.copy(authors = listOf("Anonymous")), null, known, markSaved = false).authorIdentitiesJSON)
        assertEquals("a work page read now wins", "[now]",
            merger.merge(silent, AO3WorkMetadata(authorIdentitiesJSON = "[now]"), known, markSaved = false).authorIdentitiesJSON)
    }
}
