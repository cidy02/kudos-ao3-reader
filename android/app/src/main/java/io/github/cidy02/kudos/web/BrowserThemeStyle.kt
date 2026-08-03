package io.github.cidy02.kudos.web

import android.util.Base64
import io.github.cidy02.kudos.core.model.AppThemeSetting
import io.github.cidy02.kudos.network.ao3.browse.AO3BrowseUrls
import java.nio.charset.StandardCharsets

/**
 * Scoped AO3 site skin for the in-app WebView fallback. Ports iOS
 * `BrowserThemeStyle` in `WebBrowser.swift`: maps AO3's default selectors onto
 * the app themes. Light deliberately leaves AO3's native skin untouched.
 *
 * Callers should resolve [AppThemeSetting.System] to Light or Dark (via
 * `isSystemInDarkTheme()`) before calling; System is treated as no-op (Light).
 * [AppThemeSetting.Oled] applies a true-black palette (same scheme as Dark).
 */
object BrowserThemeStyle {
    private data class Palette(
        val scheme: String,
        val background: String,
        val raised: String,
        val recessed: String,
        val text: String,
        val secondaryText: String,
        val link: String,
        val visitedLink: String,
        val border: String,
        val control: String,
        val activeControl: String
    )

    /**
     * CSS for [theme], or null when Light/System — Light leaves AO3's native
     * skin untouched (same deliberate no-op as iOS).
     */
    fun css(theme: AppThemeSetting): String? {
        val palette = palette(theme) ?: return null
        return """
        :root { color-scheme: ${palette.scheme} !important; }
        html, body, #outer, #inner, #main, #dashboard, #workskin,
        .region, .group, .group .group, .module, .index, .index .index,
        .flash, fieldset, form dl, table, th, td, textarea, input, select,
        .secondary, .dropdown, .notice, ul.notes, #modal, div.dynamic,
        .dynamic form, .autocomplete, #ui-datepicker-div {
          background-color: ${palette.background} !important;
          color: ${palette.text} !important;
          border-color: ${palette.border} !important;
          outline-color: ${palette.border} !important;
          box-shadow: none !important;
        }
        #header, #footer, #header ul.primary, #dashboard ul,
        #header .menu, #small_login, .toggled form, .listbox,
        .listbox .index, li.blurb, .blurb .blurb, blockquote,
        form blockquote.userstuff, div.comment, li.comment,
        .splash .news li, code, pre {
          background: ${palette.raised} !important;
          color: ${palette.text} !important;
          border-color: ${palette.border} !important;
          box-shadow: none !important;
        }
        #outer, .javascript, .filters .group, .thread .even,
        tr:hover, td:hover, .ui-sortable li:hover {
          background-color: ${palette.recessed} !important;
        }
        body, p, li, dt, dd, blockquote, .userstuff, .summary,
        .notes, .stats, .meta, .datetime, .byline, label,
        h1, h2, h3, h4, h5, h6, .heading, .group .heading {
          color: ${palette.text} !important;
        }
        .footnote, .help, .tip, .landmark + *, .series .divider,
        ::placeholder {
          color: ${palette.secondaryText} !important;
        }
        a, a:link, a.tag, #header a, #header a:visited,
        #dashboard a, .blurb h4 a:link, a.work {
          color: ${palette.link} !important;
        }
        a:visited, .actions a:visited, .action a:visited {
          color: ${palette.visitedLink} !important;
        }
        a:hover, a:focus, .actions a:hover, .actions button:hover,
        .actions input:hover {
          color: ${palette.link} !important;
        }
        input, textarea, select, option {
          background: ${palette.recessed} !important;
          color: ${palette.text} !important;
          border-color: ${palette.border} !important;
          box-shadow: none !important;
        }
        input:focus, textarea:focus, select:focus {
          background: ${palette.raised} !important;
          outline-color: ${palette.link} !important;
        }
        .actions a, .actions a:link, .action, .action:link,
        .actions button, .actions input, input[type="submit"], button,
        .current, .actions label, #header .actions a {
          background: ${palette.control} !important;
          background-image: none !important;
          color: ${palette.text} !important;
          border-color: ${palette.border} !important;
          box-shadow: none !important;
          text-shadow: none !important;
        }
        .actions a:active, .current, a.current, .current a:visited {
          background: ${palette.activeControl} !important;
          color: ${palette.text} !important;
          border-color: ${palette.link} !important;
        }
        li.blurb, fieldset, form dl, .picture .header,
        #header .menu li, table, th, td, hr {
          border-color: ${palette.border} !important;
        }
        mark, ::selection {
          background: ${palette.activeControl} !important;
          color: ${palette.text} !important;
        }
        """.trimIndent()
    }

    /**
     * Idempotent inject/remove script for `<style id="kudos-app-theme">`.
     * Light or non-AO3 URLs actively remove the tag (so navigating AO3 →
     * non-AO3, or switching to Light, undoes a previous injection). CSS is
     * base64-encoded and decoded with `atob` to avoid JS string-escaping issues.
     */
    fun injectionScript(theme: AppThemeSetting, url: String?): String {
        val isAo3 = url != null && AO3BrowseUrls.isAo3Url(url)
        val css = if (isAo3) css(theme) else null
        if (css == null) {
            return """
            (function(){
              var style = document.getElementById('kudos-app-theme');
              if (style) style.remove();
              if (document.documentElement) {
                document.documentElement.style.removeProperty('color-scheme');
              }
            })();
            """.trimIndent()
        }

        val encoded = Base64.encodeToString(
            css.toByteArray(StandardCharsets.UTF_8),
            Base64.NO_WRAP
        )
        return """
        (function(){
          var id = 'kudos-app-theme';
          var style = document.getElementById(id);
          if (!style) {
            style = document.createElement('style');
            style.id = id;
            (document.head || document.documentElement).appendChild(style);
          }
          style.textContent = atob('$encoded');
        })();
        """.trimIndent()
    }

    /**
     * Exact hex values from iOS `BrowserThemeStyle.palette(for:)` in
     * `WebBrowser.swift`. Light/System → null (no palette). Oled uses true-black
     * surfaces while sharing Dark's text/link/control tokens.
     */
    private fun palette(theme: AppThemeSetting): Palette? = when (theme) {
        AppThemeSetting.Light, AppThemeSetting.System -> null
        AppThemeSetting.Sepia -> Palette(
            scheme = "light",
            background = "#FBF0D9",
            raised = "#F6E8CB",
            recessed = "#ECDDBD",
            text = "#5B4636",
            secondaryText = "#79624F",
            link = "#8A5A2B",
            visitedLink = "#6F5744",
            border = "#C8B28A",
            control = "#E7D3AC",
            activeControl = "#D8BE8C"
        )
        AppThemeSetting.Dark -> Palette(
            scheme = "dark",
            background = "#16161A",
            raised = "#222228",
            recessed = "#111115",
            text = "#CFCFD4",
            secondaryText = "#A5A5AD",
            link = "#7FB0E8",
            visitedLink = "#AD93D8",
            border = "#3A3A42",
            control = "#2D2D35",
            activeControl = "#44444F"
        )
        AppThemeSetting.Oled -> Palette(
            scheme = "dark",
            background = "#000000",
            raised = "#1C1C1E",
            recessed = "#0A0A0C",
            text = "#CFCFD4",
            secondaryText = "#A5A5AD",
            link = "#7FB0E8",
            visitedLink = "#AD93D8",
            border = "#3A3A42",
            control = "#2D2D35",
            activeControl = "#44444F"
        )
    }
}
