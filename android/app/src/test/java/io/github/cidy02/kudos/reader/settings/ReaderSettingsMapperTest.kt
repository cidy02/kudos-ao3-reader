package io.github.cidy02.kudos.reader.settings

import io.github.cidy02.kudos.core.model.AppSettings
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.core.model.ReaderMode
import io.github.cidy02.kudos.core.model.ReaderSettings
import io.github.cidy02.kudos.core.model.ReaderThemeSetting
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReaderSettingsMapperTest {
    private val mapper = ReaderSettingsMapper()

    @Test
    fun defaultsMapToScrollLightFullSize() {
        val prefs = mapper.map(ReaderSettings(), AppSettings())
        assertEquals(ReaderColorTheme.Light, prefs.theme)
        assertTrue(prefs.scroll)
        assertEquals(1, prefs.columnCount)
        assertEquals(100, prefs.fontSizePercent)
        assertFalse(prefs.publisherStyles) // iOS applies comfortable defaults with Customize off
        assertFalse(prefs.justify)
    }

    @Test
    fun fontPointsMapToPercentAndClamp() {
        assertEquals(150, mapper.map(ReaderSettings(readerFontPt = 27.0), AppSettings()).fontSizePercent)
        assertEquals(50, mapper.map(ReaderSettings(readerFontPt = 4.0), AppSettings()).fontSizePercent)
        assertEquals(250, mapper.map(ReaderSettings(readerFontPt = 200.0), AppSettings()).fontSizePercent)
    }

    @Test
    fun fontPercentRoundTripsToPointsViaBase18() {
        assertEquals(18.0, ReaderSettingsMapper.fontPtFromPercent(100), 0.0)
        assertEquals(27.0, ReaderSettingsMapper.fontPtFromPercent(150), 0.0)
        assertEquals(9.0, ReaderSettingsMapper.fontPtFromPercent(50), 0.0)
        assertEquals(45.0, ReaderSettingsMapper.fontPtFromPercent(250), 0.0)
        // Out-of-range percent is clamped before conversion.
        assertEquals(9.0, ReaderSettingsMapper.fontPtFromPercent(1), 0.0)
        assertEquals(45.0, ReaderSettingsMapper.fontPtFromPercent(999), 0.0)
        // Round-trip: pt → % → pt for a clean multiple of the 18pt base.
        val percent = mapper.map(ReaderSettings(readerFontPt = 27.0), AppSettings()).fontSizePercent
        assertEquals(27.0, ReaderSettingsMapper.fontPtFromPercent(percent), 0.0)
    }

    @Test
    fun colorThemeMapsToReaderThemeSetting() {
        assertEquals(
            ReaderThemeSetting.Light,
            ReaderSettingsMapper.toReaderThemeSetting(ReaderColorTheme.Light)
        )
        assertEquals(
            ReaderThemeSetting.Sepia,
            ReaderSettingsMapper.toReaderThemeSetting(ReaderColorTheme.Sepia)
        )
        assertEquals(
            ReaderThemeSetting.Dark,
            ReaderSettingsMapper.toReaderThemeSetting(ReaderColorTheme.Dark)
        )
        assertEquals(
            ReaderThemeSetting.Oled,
            ReaderSettingsMapper.toReaderThemeSetting(ReaderColorTheme.Oled)
        )
    }

    @Test
    fun pagedTwoPageMapsToTwoColumns() {
        val prefs = mapper.map(
            ReaderSettings(readerMode = ReaderMode.Paged, readerTwoPage = true),
            AppSettings()
        )
        assertFalse(prefs.scroll)
        assertEquals(2, prefs.columnCount)
    }

    @Test
    fun customizeEnablesUserOverrides() {
        val prefs = mapper.map(ReaderSettings(readerCustomize = true, readerJustify = true), AppSettings())
        assertFalse(prefs.publisherStyles)
        assertTrue(prefs.justify)
    }

    @Test fun customizeOffResolvesLayoutOnlyAndRetainsTheSavedChoices() {
        val saved = ReaderSettings(readerCustomize = false, readerBoldText = true, readerFontId = "georgia",
            readerFontPt = 27.0, readerLineHeight = 2.4, readerLetterSpacing = 0.12,
            readerWordSpacing = 0.6, readerMargin = 64.0, readerJustify = true)
        val off = mapper.map(saved, AppSettings())
        assertEquals(1.65, off.lineHeight, 0.0)
        assertEquals(0.0, off.letterSpacingEm, 0.0)
        assertEquals(0.0, off.wordSpacingEm, 0.0)
        assertEquals(1.0, off.pageMarginsFactor, 0.0)
        assertFalse(off.justify)
        assertTrue(off.bold)
        assertEquals("serif", off.fontFamily)
        assertEquals(150, off.fontSizePercent)
        assertFalse(off.publisherStyles)
        val on = mapper.map(saved.copy(readerCustomize = true), AppSettings())
        assertEquals(2.4, on.lineHeight, 0.0)
        assertEquals(0.12, on.letterSpacingEm, 0.0)
        assertEquals(0.6, on.wordSpacingEm, 0.0)
        assertEquals(64.0 / 28.0, on.pageMarginsFactor, 0.0)
        assertTrue(on.justify)
        assertEquals(8.0 / 28.0,
            mapper.map(saved.copy(readerCustomize = true, readerMargin = 8.0), AppSettings()).pageMarginsFactor, 0.0)
    }

    @Test
    fun customFontMappedToFontFamilyAndDeclarations() {
        val customFont = io.github.cidy02.kudos.core.model.CustomFont(
            name = "Literata",
            fileName = "abc-123.ttf"
        )
        val fontPathResolver: (String) -> String? = { fileName ->
            if (fileName == "abc-123.ttf") "/data/user/0/app/files/fonts/abc-123.ttf" else null
        }
        val prefs = mapper.map(
            reader = ReaderSettings(readerFontId = customFont.selectionId),
            app = AppSettings(),
            customFonts = listOf(customFont),
            fontPathResolver = fontPathResolver
        )

        assertEquals("custom:abc-123.ttf", prefs.fontFamily)
        assertEquals(1, prefs.fontDeclarations.count { it.fontPath != null })
        val decl = prefs.fontDeclarations.single { it.fontPath != null }
        assertEquals("custom:abc-123.ttf", decl.fontFamily)
        assertEquals("/data/user/0/app/files/fonts/abc-123.ttf", decl.fontPath)
        assertEquals(listOf("serif"), decl.alternates)
    }

    @Test
    fun customFontWithoutCustomFontListResolvedViaPathResolver() {
        val fontPathResolver: (String) -> String? = { fileName ->
            if (fileName == "xyz-789.otf") "/data/user/0/app/files/fonts/xyz-789.otf" else null
        }
        val prefs = mapper.map(
            reader = ReaderSettings(readerFontId = "custom:xyz-789.otf"),
            app = AppSettings(),
            customFonts = emptyList(),
            fontPathResolver = fontPathResolver
        )

        assertEquals("custom:xyz-789.otf", prefs.fontFamily)
        assertEquals(1, prefs.fontDeclarations.count { it.fontPath != null })
        val decl = prefs.fontDeclarations.single { it.fontPath != null }
        assertEquals("custom:xyz-789.otf", decl.fontFamily)
        assertEquals("/data/user/0/app/files/fonts/xyz-789.otf", decl.fontPath)
    }

    // iOS builtInFontsKeepFallbacksAndImportedFontsInjectFontFace. iOS's built-ins are not on
    // Android, and Readium refuses a family declared with no face (the reader crashed on open
    // once every built-in was declared), so each reads as its generic family instead.
    @Test fun builtInFontsReadAsTheirGenericFamilyAndDeclareNoFace() {
        assertEquals("serif", mapper.map(ReaderSettings(readerFontId = "nyserif"), AppSettings()).fontFamily)
        assertEquals("sans-serif", mapper.map(ReaderSettings(readerFontId = "avenir"), AppSettings()).fontFamily)
        assertEquals("monospace", mapper.map(ReaderSettings(readerFontId = "menlo"), AppSettings()).fontFamily)
        io.github.cidy02.kudos.core.model.ReaderFontCatalog.builtIns.forEach { option ->
            assertTrue(mapper.map(ReaderSettings(readerFontId = option.id), AppSettings())
                .fontDeclarations.all { it.fontPath != null })
        }
    }

    @Test
    fun fontDeclarationsStayStableAcrossEveryBuiltInChoice() {
        val prefs = mapper.map(
            reader = ReaderSettings(readerFontId = "system"),
            app = AppSettings()
        )

        assertEquals(null, prefs.fontFamily)
        io.github.cidy02.kudos.core.model.ReaderFontCatalog.builtIns.forEach { option ->
            assertEquals(prefs.fontDeclarations,
                mapper.map(ReaderSettings(readerFontId = option.id), AppSettings()).fontDeclarations)
        }
    }
}

class ReaderThemeMappingTest {
    private val mapper = ReaderSettingsMapper()

    @Test
    fun matchAppThemeFollowsAppTheme() {
        fun themeFor(app: AppThemeSetting) =
            mapper.resolveTheme(ReaderSettings(matchAppReaderTheme = true), AppSettings(appTheme = app))

        assertEquals(ReaderColorTheme.Dark, themeFor(AppThemeSetting.Dark))
        assertEquals(ReaderColorTheme.Oled, themeFor(AppThemeSetting.Oled))
        assertEquals(ReaderColorTheme.Sepia, themeFor(AppThemeSetting.Sepia))
        assertEquals(ReaderColorTheme.Light, themeFor(AppThemeSetting.Light))
        // System has no EPUB equivalent -> documented Light fallback.
        assertEquals(ReaderColorTheme.Light, themeFor(AppThemeSetting.System))
    }

    @Test
    fun explicitReaderThemeIgnoresAppThemeWhenNotMatching() {
        val prefs = mapper.resolveTheme(
            ReaderSettings(matchAppReaderTheme = false, readerTheme = ReaderThemeSetting.Sepia),
            AppSettings(appTheme = AppThemeSetting.Dark)
        )
        assertEquals(ReaderColorTheme.Sepia, prefs)
    }

    @Test
    fun lightDarkSepiaOledAllSupported() {
        val mapped = ReaderThemeSetting.entries.map { setting ->
            mapper.resolveTheme(
                ReaderSettings(matchAppReaderTheme = false, readerTheme = setting),
                AppSettings()
            )
        }
        assertTrue(
            mapped.containsAll(
                listOf(
                    ReaderColorTheme.Light,
                    ReaderColorTheme.Dark,
                    ReaderColorTheme.Sepia,
                    ReaderColorTheme.Oled
                )
            )
        )
    }
}
