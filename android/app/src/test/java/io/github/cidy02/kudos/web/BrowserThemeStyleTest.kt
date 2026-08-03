package io.github.cidy02.kudos.web

import io.github.cidy02.kudos.core.model.AppThemeSetting
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BrowserThemeStyleTest {
    @Test
    fun lightReturnsNullCss() {
        assertNull(BrowserThemeStyle.css(AppThemeSetting.Light))
        assertNull(BrowserThemeStyle.css(AppThemeSetting.System))
    }

    @Test
    fun sepiaReturnsIosPaletteColors() {
        val css = BrowserThemeStyle.css(AppThemeSetting.Sepia)
        assertNotNull(css)
        // Exact hex from iOS BrowserThemeStyle.palette(for: .sepia)
        assertTrue(css!!.contains("#FBF0D9"))
        assertTrue(css.contains("#F6E8CB"))
        assertTrue(css.contains("#ECDDBD"))
        assertTrue(css.contains("#5B4636"))
        assertTrue(css.contains("#79624F"))
        assertTrue(css.contains("#8A5A2B"))
        assertTrue(css.contains("#6F5744"))
        assertTrue(css.contains("#C8B28A"))
        assertTrue(css.contains("#E7D3AC"))
        assertTrue(css.contains("#D8BE8C"))
        assertTrue(css.contains("color-scheme: light"))
    }

    @Test
    fun darkReturnsIosPaletteColors() {
        val css = BrowserThemeStyle.css(AppThemeSetting.Dark)
        assertNotNull(css)
        // Exact hex from iOS BrowserThemeStyle.palette(for: .dark)
        assertTrue(css!!.contains("#16161A"))
        assertTrue(css.contains("#222228"))
        assertTrue(css.contains("#111115"))
        assertTrue(css.contains("#CFCFD4"))
        assertTrue(css.contains("#A5A5AD"))
        assertTrue(css.contains("#7FB0E8"))
        assertTrue(css.contains("#AD93D8"))
        assertTrue(css.contains("#3A3A42"))
        assertTrue(css.contains("#2D2D35"))
        assertTrue(css.contains("#44444F"))
        assertTrue(css.contains("color-scheme: dark"))
    }

    @Test
    fun oledReturnsIosPaletteColors() {
        val css = BrowserThemeStyle.css(AppThemeSetting.Oled)
        assertNotNull(css)
        // Exact hex from iOS BrowserThemeStyle.palette(for: .oled)
        assertTrue(css!!.contains("#000000"))
        assertTrue(css.contains("#1C1C1E"))
        assertTrue(css.contains("#0A0A0C"))
        assertTrue(css.contains("#CFCFD4"))
        assertTrue(css.contains("#A5A5AD"))
        assertTrue(css.contains("#7FB0E8"))
        assertTrue(css.contains("#AD93D8"))
        assertTrue(css.contains("#3A3A42"))
        assertTrue(css.contains("#2D2D35"))
        assertTrue(css.contains("#44444F"))
        assertTrue(css.contains("color-scheme: dark"))
    }

    @Test
    fun lightOrNonAo3InjectionRemovesThemeTag() {
        val light = BrowserThemeStyle.injectionScript(
            AppThemeSetting.Light,
            "https://archiveofourown.org/media"
        )
        assertTrue(light.contains("kudos-app-theme"))
        assertTrue(light.contains("style.remove()"))
        assertFalse(light.contains("atob("))

        val nonAo3 = BrowserThemeStyle.injectionScript(
            AppThemeSetting.Dark,
            "https://example.com/"
        )
        assertTrue(nonAo3.contains("style.remove()"))
        assertFalse(nonAo3.contains("atob("))
    }

    @Test
    fun darkAo3InjectionEncodesCssWithAtob() {
        val script = BrowserThemeStyle.injectionScript(
            AppThemeSetting.Dark,
            "https://archiveofourown.org/works/1"
        )
        assertTrue(script.contains("kudos-app-theme"))
        assertTrue(script.contains("atob("))
        assertTrue(script.contains("style.textContent"))
    }
}
