package io.github.cidy02.kudos.update

/**
 * A bare `major.minor.patch` version, ignoring any leading `v` or trailing
 * `-channel` suffix (e.g. `-alpha`). Android is Alpha-channel until it reaches
 * iOS feature parity; the channel label is informational only — there is
 * exactly one Android channel today, so numeric precedence is all comparisons
 * need. If a real multi-channel scheme (alpha vs beta vs stable) is introduced
 * later, this will need proper semver pre-release precedence, not just this.
 */
data class AppVersion(
    val major: Int,
    val minor: Int,
    val patch: Int
) : Comparable<AppVersion> {
    override fun compareTo(other: AppVersion): Int {
        if (major != other.major) return major.compareTo(other.major)
        if (minor != other.minor) return minor.compareTo(other.minor)
        return patch.compareTo(other.patch)
    }

    override fun toString(): String = "$major.$minor.$patch"

    companion object {
        private val PATTERN = Regex("""v?(\d+)\.(\d+)\.(\d+)""")

        /** Parses the first `X.Y.Z` run found anywhere in [text], or null. */
        fun parse(text: String): AppVersion? {
            val match = PATTERN.find(text) ?: return null
            val (major, minor, patch) = match.destructured
            return AppVersion(
                major.toIntOrNull() ?: return null,
                minor.toIntOrNull() ?: return null,
                patch.toIntOrNull() ?: return null
            )
        }
    }
}
