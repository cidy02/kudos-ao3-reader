package io.github.cidy02.kudos.settings

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Guards brief 3i-fix: the Settings redesign once dropped 53 controls. Each label here is a
 * control the old Settings screen had; it must still be drawn somewhere in `settings/`.
 * Case-insensitive, because the redesign takes iOS's casing ("App Theme").
 */
class SettingsStringsTest {
    private val restored = listOf(
        "App Theme", "Reader Theme",
        "Text size", "Customize Theme…", "Import font",
        "Could not import font.", "Could not delete font.",
        // Import results now come from the app-wide import path (KudosApp), not this page.
        "Check Now",
        "Check library for deleted/hidden works on AO3.",
        "Auto Sync", "Disconnect", "Select sync folder", "Change sync folder", "Sync Now",
        "Require biometric to reveal", "Clear Reading History", "Clear Browse Cache",
        "Reset settings to defaults", "Software Update", "Install Update", "Source on GitHub",
        "Kudos Android is Alpha until it reaches iOS feature parity"
    )

    @Test
    fun everyOldSettingsControlIsStillDrawn() {
        val files = File("src/main/java/io/github/cidy02/kudos/settings").listFiles { f -> f.extension == "kt" }!!.toList() +
            File("src/main/java/io/github/cidy02/kudos/backup/BackupScreen.kt")
        val source = files.joinToString("\n") { it.readText() }
        val missing = restored.filterNot { source.contains(it, ignoreCase = true) }
        assertTrue("Settings lost: $missing", missing.isEmpty())
    }

    @Test fun spacingControlsRemainInCustomizeThemeWithoutAnExtraAppearanceSection() {
        val appearance = File("src/main/java/io/github/cidy02/kudos/settings/SettingsPages.kt")
            .readText().substringBefore("fun SettingsReaderPage")
        assertTrue(appearance.contains("TextSizeSlider("))
        assertTrue(appearance.contains("Customize Theme…"))
        assertTrue(!appearance.contains("updateReaderCustomize(true)"))
        for (label in listOf("Line height", "Letter spacing", "Word spacing", "Margin")) {
            assertTrue(!appearance.contains("label = \"$label\""))
        }
        val sheet = File("src/main/java/io/github/cidy02/kudos/reader/CustomizeThemeSheet.kt").readText()
        for (label in listOf("Line Spacing", "Character Spacing", "Word Spacing", "Margins")) {
            assertTrue("Customize Theme lost $label", sheet.contains("ThemeSlider(\"$label\""))
        }
    }

    @Test fun workPickerAllowsAnyFileForImporterFeedback() {
        org.junit.Assert.assertArrayEquals(arrayOf("*/*"), EpubOpenMimeTypes)
    }
}
