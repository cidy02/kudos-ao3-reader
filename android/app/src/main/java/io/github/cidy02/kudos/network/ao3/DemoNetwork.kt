package io.github.cidy02.kudos.network.ao3

import android.content.Intent
import android.content.res.AssetManager
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody

/**
 * Local stand-in for iOS `DemoNetworkBlock`. While the debug demo extra is on,
 * every `archiveofourown.org` call is answered from bundled fixtures or refused
 * on the device. AO3 is never contacted. Off, the interceptor calls through.
 *
 * The block is installed on every app OkHttp client at build time and only
 * flips on in [activate]. Clients are created in [io.github.cidy02.kudos.KudosApplication]
 * before [io.github.cidy02.kudos.MainActivity] has read the launch extra, so a
 * client built "only when the extra is on" would already have missed the race.
 */
internal fun interface FixtureSource {
    fun read(name: String): ByteArray?
}

internal object DemoNetwork {
    const val EXTRA = "kudosDemoLibrary"
    /** `--ez kudosDemoSignedIn true` with the demo: a local session as iOS `-KudosDemoSignedIn YES`. */
    const val SIGNED_IN_EXTRA = "kudosDemoSignedIn"

    /** Design review only: a demo session answered by the fixtures. AO3 is never contacted. */
    @Volatile
    var signedIn: Boolean = false
        private set

    @Volatile
    var isActive: Boolean = false
        private set

    @Volatile
    var fixtures: FixtureSource = FixtureSource { null }
        private set

    private val launchDecision = CountDownLatch(1)

    /** Fixtures are published before [isActive], so a reader that sees active also sees them. */
    fun activate(assets: AssetManager, signedIn: Boolean = false) {
        this.signedIn = signedIn
        fixtures = AssetFixtureSource(assets)
        isActive = true
        launchDecision.countDown()
    }

    /**
     * This launch is not the demo. Does not clear [isActive]: a later file-open
     * intent without the extra must not open the network after a demo start.
     */
    fun markNotDemo() {
        launchDecision.countDown()
    }

    /** Startup metadata refresh waits here so it cannot beat [activate]. */
    fun awaitLaunchDecision() {
        try {
            launchDecision.await(LAUNCH_WAIT_SECONDS, TimeUnit.SECONDS)
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
        }
    }

    fun isRequested(intent: Intent?): Boolean {
        if (intent == null) return false
        return intent.getBooleanExtra(EXTRA, false) ||
            intent.getStringExtra(EXTRA).equals("true", ignoreCase = true)
    }

    private const val LAUNCH_WAIT_SECONDS = 3L
}

private class AssetFixtureSource(
    private val assets: AssetManager
) : FixtureSource {
    override fun read(name: String): ByteArray? = try {
        assets.open("fixtures/$name.html").use { it.readBytes() }
    } catch (_: IOException) {
        null
    }
}

/**
 * Path pattern to fixture file, first match wins. Same table and same
 * unanchored matching as iOS `DemoNetworkBlock.routes` (`range(of: .regularExpression)`).
 */
internal object DemoNetworkRoutes {
    private val routes: List<Pair<Regex, String>> = listOf(
        "^/works/new" to "ao3_work_new_draft",
        "^/works/\\d+/edit" to "ao3_work_edit",
        "^/works/\\d+/navigate" to "ao3_chapter_navigate",
        "comments" to "ao3_comments_page",
        "^/works/45678901/?$" to "ao3_demo_subscription_pink",
        "^/works/12345/?$" to "ao3_demo_subscription_another",
        "^/works/999000002/?$" to "ao3_demo_subscription_cranes",
        "^/works/999000003/?$" to "ao3_demo_ashfall",
        "^/works/\\d+" to "ao3_work_bookmarked_subscribed",
        "edit_multiple" to "ao3_edit_multiple",
        "^/series/\\d+/edit" to "ao3_series_edit",
        "^/series/999/?$" to "ao3_demo_series",
        "^/collections/[^/]+/signups/\\d+" to "ao3_challenge_signup",
        "^/collections/[^/]+/signups" to "ao3_challenge_signups",
        "^/collections/[^/]+/assignments" to "ao3_challenge_assignments",
        "^/collections/[^/]+/(gift_exchange|prompt_meme)" to "ao3_challenge_settings",
        "^/collections/[^/]+/items" to "ao3_collection_items",
        "^/collections/[^/]+/participants" to "ao3_collection_participants",
        "^/collections/[^/]+/profile" to "ao3_collection_show",
        "^/collections/[^/]+/edit" to "ao3_collection_edit",
        "^/collections/[^/]+/requests" to "ao3_challenge_requests",
        "^/collections/[^/]+/works" to "ao3_tag_works",
        "^/collections/winter_exchange/bookmarks/?$" to "ao3_demo_collection_bookmarks",
        "^/collections/winter_exchange/people/?$" to "ao3_demo_collection_people",
        "^/collections/[^/]+/?$" to "ao3_collection_show",
        "^/users/[^/]+/collections" to "ao3_collections_index",
        "^/tag_sets/\\d+" to "ao3_tag_set",
        "^/media/[^/]+/fandoms" to "ao3_media_fandoms",
        "^/media/?$" to "ao3_media",
        "^/tags/[^/]+/works" to "ao3_tag_works",
        "^/works/search" to "ao3_tag_works",
        "^/users/[^/]+/(pseuds/[^/]+/)?works" to "ao3_author_works",
        "^/users/[^/]+/(pseuds/[^/]+/)?gifts" to "ao3_author_works",
        "^/users/[^/]+/(pseuds/[^/]+/)?series" to "ao3_author_series",
        "^/users/AO3_Reader/bookmarks/?$" to "ao3_demo_account_bookmarks",
        "^/users/[^/]+/(pseuds/[^/]+/)?bookmarks" to "ao3_author_bookmarks",
        "^/users/[^/]+/readings" to "ao3_readings",
        "^/users/[^/]+/subscriptions" to "ao3_subscriptions",
        "^/users/[^/]+/inbox" to "ao3_inbox_manage",
        "^/users/[^/]+/preferences" to "ao3_preferences",
        "^/users/[^/]+/stats" to "ao3_user_stats",
        "^/users/[^/]+/profile" to "ao3_author_profile",
        "^/users/[^/]+/pseuds/[^/]+/?$" to "ao3_author_pseud_dashboard",
        "^/users/[^/]+/?$" to "ao3_author_dashboard_demo",
        "^/help/preferences_privacy" to "ao3_help_preferences_privacy",
        "^/?$" to "ao3_logged_in"
    ).map { (pattern, name) -> Regex(pattern) to name }

    fun fixtureName(path: String): String? =
        routes.firstOrNull { (pattern, _) -> pattern.containsMatchIn(path) }?.second

    /** Subscriptions share a path, so their type query selects the fixture. */
    fun fixtureName(url: HttpUrl): String? {
        val path = decodedPath(url)
        if (Regex("^/users/[^/]+/subscriptions/?$").matches(path)) {
            return when (url.queryParameter("type")) {
                "series" -> "ao3_demo_subscriptions_series"
                "users" -> "ao3_demo_subscriptions_users"
                else -> "ao3_subscriptions"
            }
        }
        return fixtureName(path)
    }

    /** OkHttp [HttpUrl.pathSegments] are decoded, matching iOS `URL.path`. */
    fun decodedPath(url: HttpUrl): String {
        val segments = url.pathSegments
        if (segments.isEmpty() || (segments.size == 1 && segments[0].isEmpty())) return "/"
        return "/" + segments.joinToString("/")
    }

    fun isAo3Host(host: String): Boolean {
        val lower = host.lowercase()
        return lower == AO3Constants.WORKS_HOST || lower.endsWith(".${AO3Constants.WORKS_HOST}")
    }
}

internal class DemoNetworkInterceptor(
    private val isActive: () -> Boolean = { DemoNetwork.isActive },
    private val fixtures: () -> FixtureSource = { DemoNetwork.fixtures }
) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        if (!isActive()) return chain.proceed(chain.request())
        val url = chain.request().url
        if (!DemoNetworkRoutes.isAo3Host(url.host)) return chain.proceed(chain.request())
        val path = DemoNetworkRoutes.decodedPath(url)
        val matchTarget = if (url.queryParameter("show_comments") == "true") "$path/comments" else path
        val name = if (matchTarget == path) DemoNetworkRoutes.fixtureName(url) else DemoNetworkRoutes.fixtureName(matchTarget)
        val bytes = name?.let { fixtures().read(it) }
        val code = if (bytes == null) 404 else 200
        return Response.Builder()
            .request(chain.request())
            .protocol(Protocol.HTTP_1_1)
            .code(code)
            .message(if (code == 200) "OK" else "Not Found")
            .header("Content-Type", HTML)
            .body((bytes ?: ByteArray(0)).toResponseBody(HTML_TYPE))
            .build()
    }

    private companion object {
        const val HTML = "text/html; charset=utf-8"
        val HTML_TYPE = HTML.toMediaType()
    }
}

internal fun OkHttpClient.Builder.installDemoNetworkBlock(): OkHttpClient.Builder =
    addInterceptor(DemoNetworkInterceptor())
