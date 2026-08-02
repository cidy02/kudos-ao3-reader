package io.github.cidy02.kudos.update

import io.github.cidy02.kudos.network.github.GitHubRelease
import io.github.cidy02.kudos.network.github.GitHubReleaseAsset

/**
 * Picks the Android release meant to be installed by this checker.
 *
 * This repo's releases are shared across iOS and Android and have no history
 * of a clean tag scheme (existing tags are ad-hoc iOS sideload-test builds).
 * Rather than depend on a naming convention future CI has to remember to
 * honor, the signal is self-describing: **not draft, and it has an `.apk`
 * asset attached**. The `android-` tag prefix (see [TAG_PATTERN]) is an
 * additional, not sole, filter — it keeps this from ever matching a release
 * that happens to carry an unrelated `.apk`-named asset for some other
 * reason, while the asset check keeps it from depending on tag discipline
 * alone. Established here as the convention going forward: Android release
 * tags should look like `android-v0.1.0-alpha` (Android is Alpha-channel
 * until it reaches iOS feature parity; the channel word is a label, not part
 * of the version comparison — see [AppVersion]).
 */
object AndroidReleaseMatcher {
    private val TAG_PATTERN = Regex("""^android-v?\d+\.\d+\.\d+""", RegexOption.IGNORE_CASE)

    data class Match(
        val release: GitHubRelease,
        val version: AppVersion,
        val apk: GitHubReleaseAsset
    )

    /** The newest matching Android release, or null if none qualify. */
    fun latest(releases: List<GitHubRelease>): Match? {
        return releases
            .asSequence()
            .filter { !it.draft }
            .filter { TAG_PATTERN.containsMatchIn(it.tagName) }
            .mapNotNull { release ->
                val version = AppVersion.parse(release.tagName) ?: return@mapNotNull null
                val apk = release.assets.firstOrNull { it.name.endsWith(".apk", ignoreCase = true) }
                    ?: return@mapNotNull null
                Match(release, version, apk)
            }
            .maxByOrNull { it.version }
    }
}
