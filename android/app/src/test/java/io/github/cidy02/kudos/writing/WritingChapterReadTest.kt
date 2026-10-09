package io.github.cidy02.kudos.writing

import io.github.cidy02.kudos.network.ao3.*
import io.github.cidy02.kudos.network.ao3.writing.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class WritingChapterReadTest {
    @Test fun oneRepositoryReadForNewAndExistingOnEitherWorkAndNoEnrichment() = runTest {
        for ((work, chapter, kind) in listOf(Triple(995006L, null, "new"), Triple(995006L, 12302L, "posted"),
            Triple(995001L, null, "new"), Triple(995001L, 12311L, "draft"))) {
            val setup = workFormSetup()
            setup.client.body = workFixture("ao3_demo_chapter_${work}_$kind")
            val result = setup.repository.loadChapterForm(work, chapter)
            assertEquals(chapter, (result as AO3Result.Success).value.chapterID)
            assertEquals(listOf(AO3ChapterUrls.form(work, chapter)), setup.client.gets)
            assertEquals(0, setup.client.posts)
        }
    }

    @Test fun signedOutReadsNothingAndRefusalMakesOneAttemptWithoutRetry() = runTest {
        val out = workFormSetup(false)
        assertEquals(AO3Result.Failure(AO3Error.AuthenticationRequired), out.repository.loadChapterForm(995006, null))
        assertTrue(out.client.gets.isEmpty())
        val denied = workFormSetup()
        denied.client.failure = AO3Error.Forbidden
        assertEquals(AO3Result.Failure(AO3Error.Forbidden), denied.repository.loadChapterForm(995006, null))
        assertEquals(1, denied.client.gets.size); assertEquals(0, denied.client.posts)
    }

    @Test fun mismatchedIdentityIsNotPublishedAndChangedSessionCancelsOpening() = runTest {
        val wrong = workFormSetup()
        wrong.client.body = workFixture("ao3_demo_chapter_995001_new")
        assertTrue(wrong.repository.loadChapterForm(995006, null) is AO3Result.Failure)
        val changed = workFormSetup()
        changed.client.beforeResponse = { changed.auth.logout() }
        try { changed.repository.loadChapterForm(995006, null); fail("Old session must not publish") }
        catch (_: CancellationException) { }
        assertEquals(1, changed.client.gets.size)
    }
}
