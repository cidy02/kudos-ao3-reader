package io.github.cidy02.kudos.library

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import io.github.cidy02.kudos.data.preferences.SettingsRepository
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3WorkSummary
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SeriesPreservationPromptTest {
    @get:Rule val folder = TemporaryFolder()
    private fun page(count: Int, pages: Int = 1) = AO3SearchPage((1..count).map {
        AO3WorkSummary(it.toLong(), "Work $it", emptyList(), emptyList(), "", emptyList(), emptyList())
    }, 1, pages)

    @Test fun settingOffNeverAutoPreservesEvenBelowTheLimit() {
        assertFalse(SeriesPreservationPrompt(page(2), 5).shouldAutoPreserve(false))
    }
    @Test fun settingOnIncludesTheThresholdAndRejectsLargerSeries() {
        assertTrue(SeriesPreservationPrompt(page(3), 4).shouldAutoPreserve(true))
        assertTrue(SeriesPreservationPrompt(page(4), 4).shouldAutoPreserve(true))
        assertFalse(SeriesPreservationPrompt(page(5), 4).shouldAutoPreserve(true))
    }
    @Test fun morePagesAndFailedPreviewAlwaysNeedExplicitChoice() {
        assertFalse(SeriesPreservationPrompt(page(2, pages = 2), 25).shouldAutoPreserve(true))
        assertFalse(SeriesPreservationPrompt(null, 25, previewFailed = true).shouldAutoPreserve(true))
        assertFalse(SeriesPreservationPrompt(null, 25).canUsePreviewForPreservation)
    }
    @Test fun thresholdAndToggleComeFromTheStoredSettingRatherThanFive() = runTest {
        val dataStore = PreferenceDataStoreFactory.create(produceFile = { java.io.File(folder.root, "series.preferences_pb") })
        val settings = SettingsRepository(dataStore)
        settings.updateAutoPreserveSmallSeries(true)
        settings.updateAutoPreserveSeriesThreshold(2)
        var app = settings.snapshot().app
        var prompt = SeriesPreservationPrompt(page(3), app.autoPreserveSeriesWorkThreshold)
        assertFalse(prompt.shouldAutoPreserve(app.autoPreserveSmallSeriesOnSaveForLater))
        assertEquals("Always auto-preserve series under 2 works", prompt.autoPreserveLabel)
        settings.updateAutoPreserveSeriesThreshold(3)
        app = settings.snapshot().app
        prompt = SeriesPreservationPrompt(page(3), app.autoPreserveSeriesWorkThreshold)
        assertTrue(prompt.shouldAutoPreserve(app.autoPreserveSmallSeriesOnSaveForLater))
        settings.updateAutoPreserveSmallSeries(false)
        assertFalse(prompt.shouldAutoPreserve(settings.snapshot().app.autoPreserveSmallSeriesOnSaveForLater))
    }
    @Test fun promptWordsMatchSwiftIncludingSingularAndUnknownSize() {
        assertEquals("This series has 1 work. Download every work in the series?", SeriesPreservationPrompt(page(1), 5).message)
        assertEquals("This series has 3 works. Download every work in the series?", SeriesPreservationPrompt(page(3), 5).message)
        assertEquals("This series has at least 3 works and more may be on other pages. Download every work in the series?",
            SeriesPreservationPrompt(page(3, 2), 5).message)
        assertEquals("Kudos couldn't check how many works are in this series. Continuing may download many works. Kudos adds them one at a time.",
            SeriesPreservationPrompt(null, 5, true).message)
    }
    @Test fun everyResultSentenceMatchesSwift() {
        assertEquals("Preserving series…", SeriesPreservationResult().progressText())
        assertEquals("Preserving series 2 of 4…", SeriesPreservationResult(total = 4, preserved = 2).progressText())
        assertEquals("Series preservation cancelled. Preserved 1 work.", SeriesPreservationResult(preserved = 1, cancelled = 2).completionText())
        assertEquals("Series preservation cancelled. Preserved 2 works.", SeriesPreservationResult(preserved = 2, cancelled = 2).completionText())
        assertEquals("No other series works were found.", SeriesPreservationResult(failed = 1).completionText())
        assertEquals("Series works are already preserved for later.", SeriesPreservationResult(total = 1).completionText())
        val result = SeriesPreservationResult(total = 5, preserved = 1, alreadyPreserved = 1, unavailable = 1, failed = 1, skipped = 1)
        assertEquals("Series preservation complete: 1 preserved, 1 already preserved, 1 unavailable, 1 failed, 1 skipped.", result.completionText())
        assertEquals("Adding 5 of 5 series works…", result.queueText(true))
        assertEquals("1 added, 1 already preserved, 1 unavailable, 1 failed, 1 skipped.", result.queueText(false))
        assertEquals("Stopped adding the series. 1 work was added.", SeriesPreservationResult(preserved = 1, cancelled = 1).queueText(false))
        assertEquals("Stopped adding the series. 2 works were added.", SeriesPreservationResult(preserved = 2, cancelled = 1).queueText(false))
        assertEquals("No series works were found.", SeriesPreservationResult(failed = 1).queueText(false))
        assertEquals("Series works are already in the selected queues.", SeriesPreservationResult(total = 1).queueText(false))
    }
}
