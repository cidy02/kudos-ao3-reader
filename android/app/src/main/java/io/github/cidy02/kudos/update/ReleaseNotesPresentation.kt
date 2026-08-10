package io.github.cidy02.kudos.update

import io.github.cidy02.kudos.network.github.GitHubRelease
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Pure presentation helpers for GitHub release notes in the Software Update UI.
 *
 * Release bodies are Markdown on GitHub; this project has no Markdown renderer
 * dependency, so [notesForDisplay] returns the body as plain text with
 * structure (line breaks, list markers) preserved rather than parsed.
 */
object ReleaseNotesPresentation {
    private val publishedDateFormatter: DateTimeFormatter =
        DateTimeFormatter.ofPattern("MMM d, yyyy", Locale.US)

    /** Fallback when the release has no usable body. */
    const val EMPTY_NOTES_FALLBACK = "No release notes for this version."

    /**
     * Title line: prefer the GitHub release [GitHubRelease.name] when present,
     * otherwise a version-only label so the panel is never blank.
     */
    fun title(release: GitHubRelease, version: AppVersion): String {
        val name = release.name?.trim().orEmpty()
        return if (name.isNotEmpty()) name else "Version $version"
    }

    /**
     * Human-readable published date from GitHub's ISO-8601 [GitHubRelease.publishedAt],
     * or null when missing/unparseable (caller omits the date row).
     */
    fun formatPublishedDate(publishedAt: String?): String? {
        val raw = publishedAt?.trim().orEmpty()
        if (raw.isEmpty()) return null
        return try {
            val instant = Instant.parse(raw)
            publishedDateFormatter.format(instant.atZone(ZoneOffset.UTC))
        } catch (_: Exception) {
            // Show the raw stamp rather than dropping a date GitHub did send.
            raw
        }
    }

    /**
     * Body text for the notes panel. Trims whitespace; empty/blank bodies use
     * [EMPTY_NOTES_FALLBACK] so the UI never renders a blank notes area.
     * Markdown is left as-is (no parser) — readable raw text is intentional.
     */
    fun notesForDisplay(body: String?): String {
        val trimmed = body?.trim().orEmpty()
        return if (trimmed.isEmpty()) EMPTY_NOTES_FALLBACK else trimmed
    }
}
