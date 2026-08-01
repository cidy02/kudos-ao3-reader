package io.github.cidy02.kudos.network.ao3

/**
 * Single source of the AO3 User-Agent string.
 *
 * Must match Apple `AO3RequestDefaults.userAgent`: a Safari-shaped base plus an
 * identifiable `KudosReader/<version> (+repo)` token so AO3 operators can
 * distinguish polite Kudos traffic from generic scraping.
 *
 * Invariant: do not construct a second UA string elsewhere — see
 * `Scripts/check-invariants.sh`.
 */
object AO3UserAgent {
    const val APP_VERSION: String = "0.1.0"

    const val VALUE: String =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 " +
            "KudosReader/$APP_VERSION (+https://github.com/cidy02/kudos-ao3-reader)"
}
