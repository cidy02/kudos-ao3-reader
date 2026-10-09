package io.github.cidy02.kudos.network.ao3

import android.content.Intent
import android.content.res.AssetManager
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.ConcurrentHashMap
import java.net.URLDecoder
import okhttp3.HttpUrl
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Protocol
import okhttp3.Response
import okhttp3.ResponseBody.Companion.toResponseBody
import okio.Buffer
import org.jsoup.Jsoup
import java.time.Clock
import java.time.LocalDate
import java.time.format.TextStyle
import java.util.Locale
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import kotlinx.serialization.json.add

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
    /** Read-only browser fallback also stays local; unknown pages/subresources get a terminal 404. */
    fun webFixture(url: HttpUrl, source: FixtureSource = fixtures, clock: Clock? = null): ByteArray? {
        if (!DemoNetworkRoutes.isAo3Host(url.host)) return null
        val path = DemoNetworkRoutes.decodedPath(url).trimEnd('/')
        val name = when (path) {
            "/collections/winter_exchange/participants" -> "ao3_demo_moderation_participants"
            "/collections/winter_exchange" -> "ao3_demo_moderation_show"
            else -> DemoNetworkRoutes.fixtureName(url)
        }
        val bytes = name?.let { source.read(it) }
        return bytes?.let {
            when {
                DemoNetworkRoutes.isDraftsPath(path) -> demoDraftsPage(it, clock)
                DemoNetworkRoutes.isAuthorWorksPath(path) -> demoAuthorWorksPage(it, url)
                isDemoCommentThread(path) -> demoCommentThreadPage(it, path)
                else -> demoChallengeCollectionPage(it, path)
            }
        }
    }

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
        "^/works/995006/chapters/new/?$" to "ao3_demo_chapter_995006_new",
        "^/works/995006/chapters/12302/edit/?$" to "ao3_demo_chapter_995006_posted",
        "^/works/995006/chapters/12302/confirm_delete/?$" to "ao3_demo_chapter_995006_delete",
        "^/works/995001/chapters/new/?$" to "ao3_demo_chapter_995001_new",
        "^/works/995001/chapters/12311/edit/?$" to "ao3_demo_chapter_995001_draft",
        "^/works/995001/chapters/12311/confirm_delete/?$" to "ao3_demo_chapter_995001_delete",
        "^/works/new" to "ao3_work_new_draft",
        "^/works/995001/edit/?$" to "ao3_demo_work_draft_edit",
        "^/works/995006/edit/?$" to "ao3_demo_work_posted_edit",
        "^/works/995006/edit_tags/?$" to "ao3_demo_work_edit_tags",
        "^/works/\\d+/edit" to "ao3_work_edit",
        "^/works/995006/navigate/?$" to "ao3_demo_work_posted_navigate",
        "^/works/\\d+/navigate" to "ao3_chapter_navigate",
        "comments" to "ao3_comments_page",
        "^/works/45678901/?$" to "ao3_demo_subscription_pink",
        "^/works/12345/?$" to "ao3_demo_subscription_another",
        "^/works/999000002/?$" to "ao3_demo_subscription_cranes",
        "^/works/999000003/?$" to "ao3_demo_ashfall",
        "^/works/\\d+" to "ao3_work_bookmarked_subscribed",
        "edit_multiple" to "ao3_edit_multiple",
        "^/series/321/edit/?$" to "ao3_demo_series_edit",
        "^/series/321/manage/?$" to "ao3_demo_series_manage",
        "^/series/321/?$" to "ao3_demo_dawn_series",
        "^/series/\\d+/edit" to "ao3_series_edit",
        "^/series/999/?$" to "ao3_demo_series",
        "^/collections/new/?$" to "ao3_demo_collection_new",
        "^/collections/winter_exchange/edit/?$" to "ao3_demo_collection_edit",
        "^/collections/winter_exchange/confirm_delete/?$" to "ao3_demo_collection_destroy",
        "^/collections/winter_exchange/signups/new/?$" to "ao3_demo_signup_winter_new",
        "^/collections/winter_exchange/signups/4/edit/?$" to "ao3_demo_signup_winter_edit",
        "^/collections/summer_meme/signups/new/?$" to "ao3_demo_signup_summer_new",
        "^/collections/[^/]+/signups/\\d+" to "ao3_challenge_signup",
        "^/collections/[^/]+/signups" to "ao3_challenge_signups",
        "^/collections/[^/]+/assignments" to "ao3_challenge_assignments",
        "^/collections/[^/]+/(gift_exchange|prompt_meme)" to "ao3_challenge_settings",
        "^/collections/winter_exchange/items" to "ao3_demo_collection_items",
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
        "^/users/[^/]+/collection_items" to "ao3_demo_user_collection_items",
        "^/tag_sets/\\d+" to "ao3_tag_set",
        "^/media/[^/]+/fandoms" to "ao3_media_fandoms",
        "^/media/?$" to "ao3_media",
        "^/tags/[^/]+/works" to "ao3_tag_works",
        "^/works/search" to "ao3_tag_works",
        "^/users/[^/]+/works/drafts/?$" to "ao3_demo_drafts_1",
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
        if (Regex("^/tag_sets/(42|43|44)(?:/|$)").containsMatchIn(path)) tagSetFixture(path)
        else routes.firstOrNull { (pattern, _) -> pattern.containsMatchIn(path) }?.second

    /** One local answer per tag-set address, shared by the native screen and browser. */
    private fun tagSetFixture(path: String): String? = when (path.trimEnd('/')) {
        "/tag_sets/42" -> "ao3_demo_tag_set_42"
        "/tag_sets/42/edit" -> "ao3_demo_tag_set_42_edit"
        "/tag_sets/42/nominations" -> "ao3_demo_tag_set_42_nominations"
        "/tag_sets/42/associations" -> "ao3_demo_tag_set_42_nominations"
        "/tag_sets/43", "/tag_sets/43/edit" -> "ao3_demo_tag_set_43"
        "/tag_sets/43/nominations", "/tag_sets/43/associations" -> "ao3_demo_tag_set_43_nominations"
        "/tag_sets/44" -> "ao3_demo_tag_set_44"
        "/tag_sets/44/edit" -> "ao3_demo_tag_set_44_edit_refused"
        "/tag_sets/44/nominations", "/tag_sets/44/associations" -> "ao3_demo_tag_set_44_nominations"
        else -> null // Unknown subpages remain terminal local failures.
    }

    /** Subscriptions share a path, so their type query selects the fixture. */
    fun fixtureName(url: HttpUrl): String? {
        val path = decodedPath(url)
        if (path.trimEnd('/') == "/series/1001") return null // terminal failed preview, same for browser
        if (path.trimEnd('/') == "/series/1000") return when (url.queryParameter("page")) {
            null, "1" -> "ao3_demo_series_two_pages_1"
            "2" -> "ao3_demo_series_two_pages_2"
            else -> null
        }
        // One answer per address for both OkHttp and the demo's read-only WebView.
        if (path.trimEnd('/') == "/collections/winter_exchange/signups") return when (url.queryParameter("page")) {
            null, "1" -> "ao3_demo_winter_signups_1"
            "2" -> "ao3_demo_winter_signups_2"
            else -> null
        }
        if (path.trimEnd('/') == "/collections/winter_exchange/assignments") {
            if (url.queryParameter("page") !in listOf(null, "1")) return null
            return when {
                url.queryParameter("fulfilled") == "true" -> "ao3_demo_winter_assignments_complete"
                url.queryParameter("unfulfilled") == "true" -> "ao3_demo_winter_assignments_open"
                else -> "ao3_demo_winter_assignments_defaults"
            }
        }
        if (path.trimEnd('/') in setOf("/collections/winter_exchange/gift_exchange", "/collections/winter_exchange/gift_exchange/edit"))
            return "ao3_demo_winter_settings"
        if (path.trimEnd('/') == "/collections/winter_exchange/signups/5/edit") return "ao3_demo_signup_winter_5_edit"
        if (path.trimEnd('/') == "/collections/winter_exchange/signups/4/confirm_delete") return "ao3_demo_signup_4_confirm_delete"
        if (path.trimEnd('/') == "/collections/winter_exchange/signups/5/confirm_delete") return "ao3_demo_signup_5_confirm_delete"
        if (path.trimEnd('/') == "/collections/summer_meme/requests") return when (url.queryParameter("page")) {
            null, "1" -> "ao3_demo_meme_requests_1"
            "2" -> "ao3_demo_meme_requests_2"
            else -> null
        }
        if (path.trimEnd('/') == "/collections/summer_meme/gift_exchange/edit") return null // local 404 probes the meme
        if (path.trimEnd('/') in setOf("/collections/summer_meme/prompt_meme", "/collections/summer_meme/prompt_meme/edit"))
            return "ao3_demo_meme_settings"
        if (path.trimEnd('/') in setOf("/collections/summer_meme", "/collections/summer_meme/profile"))
            return "ao3_collection_show"
        if (path.trimEnd('/') in setOf("/collections/rare_pairs", "/collections/rare_pairs/profile"))
            return "ao3_demo_maintainers_show"
        if (path.trimEnd('/') == "/collections/rare_pairs/signups") return null // one failed count, never a fake zero
        if (isDraftsPath(path)) return if (url.queryParameter("page") == "2") "ao3_demo_drafts_2" else "ao3_demo_drafts_1"
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

    fun isDraftsPath(path: String): Boolean = Regex("^/users/[^/]+/works/drafts/?$").matches(path)

    fun isAuthorWorksPath(path: String): Boolean =
        Regex("^/users/[^/]+/(pseuds/[^/]+/)?(works(/collected)?|gifts)/?$").matches(path)
}

/**
 * One comment's own page carries that comment, as AO3's does: the Inbox's Chapter Comments looks its
 * comment up there, and the one comments fixture has ids of its own.
 */
internal fun isDemoCommentThread(path: String) = Regex("^/comments/\\d+$").matches(path)
internal fun demoCommentThreadPage(bytes: ByteArray, path: String): ByteArray =
    bytes.decodeToString().replace("comment_1001", "comment_${path.substringAfterLast('/')}").encodeToByteArray()

/** Only the drafts fixtures are rebased to today. Tests pin the same clock used by the chips. */
internal fun demoDraftsPage(bytes: ByteArray, clock: Clock? = null): ByteArray {
    val document = Jsoup.parse(bytes.decodeToString())
    val today = if (clock == null) LocalDate.now() else LocalDate.now(clock)
    for (notice in document.select("p.caution.notice[data-demo-days-left]")) {
        val offset = notice.attr("data-demo-days-left").toLongOrNull() ?: continue
        val date = today.plusDays(offset)
        notice.selectFirst("span.date")?.text(date.dayOfMonth.toString())
        notice.selectFirst("abbr.month")?.attr("title", date.month.getDisplayName(TextStyle.FULL, Locale.ENGLISH))
            ?.text(date.month.getDisplayName(TextStyle.SHORT, Locale.ENGLISH))
        notice.selectFirst("span.year")?.text(date.year.toString())
    }
    return document.outerHtml().encodeToByteArray()
}

/** Same address, same ordered/filter answer in OkHttp and the read-only demo browser. */
internal fun demoAuthorWorksPage(bytes: ByteArray, url: HttpUrl): ByteArray {
    if (DemoNetworkRoutes.decodedPath(url).trimEnd('/').endsWith("/gifts")) return bytes
    val column = url.queryParameter("work_search[sort_column]") ?: "revised_at"
    val direction = url.queryParameter("work_search[sort_direction]")
        ?: if (column in setOf("authors_to_sort_on", "title_to_sort_on")) "asc" else "desc"
    val completion = url.queryParameter("work_search[complete]")
    val doc = Jsoup.parse(bytes.decodeToString())
    val index = doc.selectFirst("ol.work.index") ?: return bytes
    val rows = index.select("li.work.blurb").toList()
    val matching = rows.filter { row ->
        when (completion) {
            "T" -> row.selectFirst(".iswip .text")?.text() == "Complete Work"
            "F" -> row.selectFirst(".iswip .text")?.text() == "Work in Progress"
            else -> true
        }
    }
    fun number(row: org.jsoup.nodes.Element, field: String): Long =
        row.selectFirst("dd.$field")?.text()?.filter(Char::isDigit)?.toLongOrNull() ?: 0
    fun key(row: org.jsoup.nodes.Element): String = when (column) {
        "authors_to_sort_on" -> row.select("a[rel=author]").text().ifBlank { "Anonymous" }.lowercase(Locale.ROOT)
        "title_to_sort_on" -> row.selectFirst("h4.heading a")?.text().orEmpty().lowercase(Locale.ROOT)
        "created_at" -> row.attr("data-demo-posted")
        "revised_at" -> LocalDate.parse(row.selectFirst("p.datetime")?.text(),
            java.time.format.DateTimeFormatter.ofPattern("dd MMM uuuu", Locale.ENGLISH)).toString()
        else -> number(row, when (column) {
            "word_count" -> "words"
            "kudos_count" -> "kudos"
            "comments_count" -> "comments"
            "bookmarks_count" -> "bookmarks"
            else -> "hits"
        }).toString().padStart(12, '0')
    }
    val ordered = matching.sortedBy(::key).let { if (direction == "desc") it.reversed() else it }
    rows.forEach { it.remove() }
    ordered.forEach { index.appendChild(it) }
    return doc.outerHtml().encodeToByteArray()
}

internal class DemoNetworkInterceptor(
    private val isActive: () -> Boolean = { DemoNetwork.isActive },
    private val fixtures: () -> FixtureSource = { DemoNetwork.fixtures },
    private val clock: Clock? = null
) : Interceptor {
    private val removedSubscriptions = ConcurrentHashMap.newKeySet<String>()
    private val collectionItems = DemoCollectionItems()
    private val userCollectionItems = DemoCollectionItems(account = true)
    private val collectionForms = DemoCollectionForms()
    private val collectionParticipants = DemoCollectionParticipants()
    private val tagSets = DemoTagSetWrites()
    private val promptMeme = DemoPromptMemeWrites()
    private val signUps = DemoChallengeSignUps()
    private val workForms = DemoWorkSaves()
    private val seriesForms = DemoSeriesWrites()

    override fun intercept(chain: Interceptor.Chain): Response {
        if (!isActive()) return chain.proceed(chain.request())
        val url = chain.request().url
        if (!DemoNetworkRoutes.isAo3Host(url.host)) return chain.proceed(chain.request())
        val path = DemoNetworkRoutes.decodedPath(url)
        seriesForms.answer(chain.request(), fixtures())?.let { answer ->
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message("Local series answer").header("Content-Type", HTML)
                .body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        workForms.answer(chain.request(), fixtures(), clock)?.let { answer ->
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message("Local work Save answer").header("Content-Type", HTML)
                .body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        // Real local EPUBs for this brief's batch; no background download escapes to AO3.
        val seriesDownload = Regex("^/downloads/(99511[0-5]|995120|99900000[2-5])/work\\.epub$").matchEntire(path)
        if (chain.request().method == "GET" && seriesDownload != null) {
            val id = seriesDownload.groupValues[1]
            val bytes = io.github.cidy02.kudos.works.converters.EpubBuilder.buildEpub(
                "Series work $id", "<p>The lantern keeper leaves a letter for the next traveller.</p>" +
                    "<p>At dawn, the reply arrives folded around a map of the road ahead.</p>")
            val type = "application/epub+zip"
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(200).message("Local series EPUB").header("Content-Type", type)
                .body(bytes.toResponseBody(type.toMediaType())).build()
        }
        if (chain.request().method == "POST" && (path.trimEnd('/') == "/bookmarks/2997787566" ||
                Regex("^/works/\\d+/bookmarks/?$").matches(path))) {
            val fields = (chain.request().body as? okhttp3.FormBody)
            val notes = fields?.let { form -> (0 until form.size).firstOrNull {
                form.name(it) == "bookmark[bookmarker_notes]"
            }?.let { form.value(it) } } ?: chain.request().body?.let { body ->
                val buffer = okio.Buffer(); body.writeTo(buffer)
                buffer.readUtf8().split('&').firstOrNull { it.startsWith("bookmark%5Bbookmarker_notes%5D=") }
                    ?.substringAfter('=')?.let { java.net.URLDecoder.decode(it, "UTF-8") }
            }.orEmpty()
            val refused = notes.length > 5000
            val html = if (refused) "<div id='error'><ul><li>Notes must be less than 5000 characters long.</li></ul></div>"
                else "<div class='flash notice'>Bookmark updated.</div>"
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(if (refused) 422 else 200).message("Local bookmark answer").header("Content-Type", HTML)
                .body(html.toResponseBody(HTML_TYPE)).build()
        }
        if (chain.request().method == "GET" && path.trimEnd('/') in setOf(
                "/autocomplete/fandom", "/autocomplete/relationship", "/autocomplete/character", "/autocomplete/freeform",
                "/autocomplete/open_collection_names")) {
            val term = url.queryParameter("term").orEmpty().trim().lowercase(Locale.ROOT)
            val names = if (term == "demo") when (path.trimEnd('/').substringAfterLast('/')) {
                "fandom" -> listOf("Demo Fandom", "Demo Fandom & 星", "Demo Fandom - Alternate Universe")
                "relationship" -> listOf("Demo A/Demo B", "Demo A & Demo B", "Demo B/Demo C")
                "character" -> listOf("Demo A", "Demo B", "Demo C")
                "open_collection_names" -> listOf("Demo Lanterns (demo_lanterns)", "Demo Atlas & 星 (demo_atlas)", "Demo Exchange (demo_exchange)")
                else -> listOf("Demo Fluff", "Demo Angst", "Demo Found Family")
            } else emptyList()
            val json = buildJsonArray { names.forEach { name -> add(buildJsonObject {
                put("id", if (path.trimEnd('/').endsWith("/open_collection_names")) name.substringAfterLast('(').removeSuffix(")") else name)
                put("name", name)
            }) } }
            val type = "application/json; charset=utf-8"
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(if (term == "fail") 403 else 200).message("Local autocomplete answer")
                .header("Content-Type", type).body(json.toString().toResponseBody(type.toMediaType())).build()
        }
        signUps.answer(chain.request(), fixtures())?.let { answer ->
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message("Local sign-up answer").header("Content-Type", HTML)
                .body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        promptMeme.answer(chain.request(), fixtures())?.let { answer ->
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message("Local prompt-meme answer").header("Content-Type", HTML)
                .body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        tagSets.answer(chain.request(), fixtures())?.let { answer ->
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message("Local tag-set answer").header("Content-Type", HTML)
                .body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        if (chain.request().method != "GET" && Regex("^/tag_sets/(42|43|44)(?:/|$)").containsMatchIn(path)) {
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(405).message("Read-only tag-set demo").header("Content-Type", HTML)
                .body("<p class='note'>This local tag-set answer is read only.</p>".toResponseBody(HTML_TYPE)).build()
        }
        collectionParticipants.answer(chain.request(), fixtures())?.let { answer ->
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message("Local participants answer").header("Content-Type", HTML)
                .body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        collectionForms.answer(chain.request(), fixtures())?.let { answer ->
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message("Local collection answer").header("Content-Type", HTML)
                .body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        if (path == "/collections/winter_exchange/items" || path == "/collections/winter_exchange/items/update_multiple") {
            val answer = collectionItems.answer(chain.request(), fixtures().read("ao3_demo_collection_items"))
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message(if (answer.first == 200) "OK" else "Unprocessable Entity")
                .header("Content-Type", HTML).body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        if (Regex("^/users/[^/]+/collection_items(?:/update_multiple)?/?$").matches(path)) {
            val answer = userCollectionItems.answer(chain.request(), fixtures().read("ao3_demo_user_collection_items"))
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(answer.first).message(if (answer.first == 200) "OK" else "Local refusal")
                .header("Content-Type", HTML).body(answer.second.toResponseBody(HTML_TYPE)).build()
        }
        // A terminal local response, including failures. Never fall through to AO3.
        if (chain.request().method == "POST" && Regex("^/users/[^/]+/subscriptions/[^/]+/?$").matches(path)) {
            val buffer = Buffer()
            chain.request().body?.writeTo(buffer)
            val fields = buffer.readUtf8().split('&').associate { field ->
                val parts = field.split('=', limit = 2)
                URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts.getOrElse(1) { "" }, "UTF-8")
            }
            val id = url.pathSegments.lastOrNull()?.toIntOrNull()
            val accepted = fields["_method"] == "delete" &&
                fields["authenticity_token"] == "demo-subscriptions-token" &&
                id != null && id in setOf(1, 3, 4, 5) && removedSubscriptions.add(path)
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(if (accepted) 200 else 422).message(if (accepted) "OK" else "Unprocessable Entity")
                .header("Content-Type", HTML)
                .body((if (accepted) "<div class='flash notice'>Unsubscribed.</div>" else
                    "<div class='flash error'>Couldn't unsubscribe.</div>").toResponseBody(HTML_TYPE))
                .build()
        }
        // One row of the demo's AO3 history, removed for this run only (the screen hides it).
        if (chain.request().method == "POST" && Regex("^/users/[^/]+/readings/\\d+/?$").matches(path)) {
            val buffer = Buffer()
            chain.request().body?.writeTo(buffer)
            val fields = buffer.readUtf8().split('&').associate { field ->
                val parts = field.split('=', limit = 2)
                URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts.getOrElse(1) { "" }, "UTF-8")
            }
            val accepted = fields["_method"] == "delete" && fields["authenticity_token"] == "demo-history-token" &&
                fields["reading"] == url.pathSegments.lastOrNull { it.isNotEmpty() }
            return Response.Builder().request(chain.request()).protocol(Protocol.HTTP_1_1)
                .code(if (accepted) 200 else 422).message(if (accepted) "OK" else "Unprocessable Entity")
                .header("Content-Type", HTML)
                .body((if (accepted) "<div class='flash notice'>Work successfully deleted from your history.</div>" else
                    "<div class='flash error'>Couldn't remove that from history.</div>").toResponseBody(HTML_TYPE))
                .build()
        }
        val matchTarget = if (url.queryParameter("show_comments") == "true") "$path/comments" else path
        val name = if (matchTarget == path) DemoNetworkRoutes.fixtureName(url) else DemoNetworkRoutes.fixtureName(matchTarget)
        var bytes = name?.let { fixtures().read(it) }
        if (bytes != null && chain.request().method == "GET") {
            bytes = when {
                DemoNetworkRoutes.isDraftsPath(path) -> demoDraftsPage(bytes, clock)
                DemoNetworkRoutes.isAuthorWorksPath(path) -> demoAuthorWorksPage(bytes, url)
                isDemoCommentThread(path.trimEnd('/')) -> demoCommentThreadPage(bytes, path.trimEnd('/'))
                else -> demoChallengeCollectionPage(bytes, path.trimEnd('/'))
            }
        }
        if (bytes != null && chain.request().method == "GET" &&
            Regex("^/users/[^/]+/subscriptions/?$").matches(path)
        ) {
            val document = Jsoup.parse(bytes.decodeToString())
            for (heading in document.select("dl.subscription dt")) {
                val details = heading.nextElementSibling()?.takeIf { it.tagName() == "dd" } ?: continue
                val action = details.selectFirst("form")?.attr("action")
                if (action != null && action in removedSubscriptions) {
                    heading.remove()
                    details.remove()
                }
            }
            bytes = document.outerHtml().encodeToByteArray()
        }
        val code = if (bytes == null) 404 else if (path.trimEnd('/') == "/tag_sets/44/edit") 403 else 200
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

/** Process-local AO3 answers. Every supported write terminates here, never at a socket. */
private class DemoWorkSaves {
    private val edited = ConcurrentHashMap<Long, String>()
    private val values = ConcurrentHashMap<Long, Map<String, List<String>>>()
    private var editedTags: String? = null
    private val chapters = DemoWritingChapters()
    private val posted = mutableSetOf(995006L)
    private val deleted = mutableSetOf<Long>()

    @Synchronized
    fun answer(request: okhttp3.Request, source: FixtureSource, clock: Clock?): Pair<Int, String>? {
        val path = DemoNetworkRoutes.decodedPath(request.url).trimEnd('/')
        val ownerID = Regex("^/works/(995001|995006|995007)(?:/.*)?$").matchEntire(path)?.groupValues?.get(1)?.toLong()
        if (ownerID != null && ownerID in deleted) return 404 to ""
        chapters.answer(request, source)?.let { return it }
        if (path == "/works/995006/edit_tags" && request.method == "GET")
            return editedTags?.let { 200 to it }
        if (path == "/works/995006/update_tags" && request.method == "POST") {
            val html = editedTags ?: source.read("ao3_demo_work_edit_tags")?.decodeToString() ?: return 404 to ""
            val doc = Jsoup.parse(html)
            val buffer = okio.Buffer()
            request.body?.writeTo(buffer)
            val fields = buffer.readUtf8().split('&').filter(String::isNotEmpty).map {
                val pair = it.split('=', limit = 2)
                URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
            }.groupBy({ it.first }, { it.second })
            val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")
            val reason = when {
                fields["authenticity_token"] != listOf(token) || request.header("X-CSRF-Token") != token ||
                    fields["update_button"] != listOf("1") || fields["_method"] != listOf("patch") -> "AO3 didn't accept the change."
                fields["work[freeform_string]"]?.firstOrNull()?.split(',')?.any { it.trim() == "Refuse this tag" } == true ->
                    "Additional tags: Refuse this tag could not be saved."
                fields["work[archive_warning_strings][]"].orEmpty().all { it.isEmpty() } -> "Please select at least one warning"
                fields["work[fandom_string]"].orEmpty().all { it.isBlank() } -> "Fandom can't be blank"
                else -> null
            }
            if (reason != null) return 422 to "<main id='main'><div id='error'><ul><li>$reason</li></ul></div></main>"
            fun applyTags(target: org.jsoup.nodes.Document) {
                for (control in target.select("form#work-form [name]")) {
                    val sent = fields[control.attr("name")] ?: continue
                    when (control.tagName()) {
                        "select" -> control.select("option").forEach { option ->
                            if (option.attr("value") in sent) option.attr("selected", "selected") else option.removeAttr("selected")
                        }
                        "input" -> if (control.attr("type") in setOf("checkbox", "radio")) {
                            if (control.attr("value") in sent) control.attr("checked", "checked") else control.removeAttr("checked")
                        } else control.attr("value", sent.firstOrNull().orEmpty())
                    }
                }
            }
            applyTags(doc)
            editedTags = doc.outerHtml()
            val work = edited[995006L] ?: source.read("ao3_demo_work_posted_edit")?.decodeToString() ?: return 404 to ""
            val workDoc = Jsoup.parse(work)
            applyTags(workDoc)
            edited[995006L] = workDoc.outerHtml()
            return 200 to "<main id='main'><div class='flash notice'>Tags were successfully updated.</div></main>"
        }
        val id = Regex("^/works/(995001|995006|995007)(?:/edit|/confirm_delete)?$").matchEntire(path)?.groupValues?.get(1)?.toLong()
        if (request.method == "GET") {
            if (id != null && path.endsWith("/confirm_delete")) {
                val base = edited[id] ?: source.read(if (id == 995006L) "ao3_demo_work_posted_edit" else "ao3_demo_work_draft_edit")?.decodeToString()
                    ?: return 404 to ""
                val title = Jsoup.parse(base).selectFirst("[name='work[title]']")?.attr("value").orEmpty()
                val draft = id !in posted
                val page = Jsoup.parse("<main id='main'><h2 class='heading'></h2><p class='caution'></p><form class='destroy' method='post' action='/works/$id'><input name='authenticity_token' value='demo-delete-$id=='><input name='_method' value='delete'></form></main>")
                page.selectFirst("h2")?.text(if (draft) "Delete Draft" else "Delete Work")
                page.selectFirst("p.caution")?.text("Are you sure you want to delete ${if (draft) "the draft" else "the work"} \"$title\"? This will delete 7 comments, 23 kudos and 4 bookmarks and cannot be undone.")
                page.head().appendElement("meta").attr("name", "csrf-token").attr("content", "demo-delete-$id==")
                return 200 to page.outerHtml()
            }
            if (id != null && !path.endsWith("/edit")) {
                if (id !in posted) return 404 to "" // Never pretend an unposted public work exists.
                val fixture = DemoNetworkRoutes.fixtureName(request.url) ?: return 404 to ""
                return source.read(fixture)?.decodeToString()?.let { 200 to it } ?: (404 to "")
            }
            if (id != null && path.endsWith("/edit")) {
                val held = edited[id]
                if (chapters.hasChanges(id)) {
                    val base = held ?: source.read(if (id == 995006L) "ao3_demo_work_posted_edit" else "ao3_demo_work_draft_edit")?.decodeToString()
                        ?: return 404 to ""
                    val doc = Jsoup.parse(base).apply { outputSettings().prettyPrint(false) }
                    chapters.applyToWork(doc, id)
                    return 200 to doc.outerHtml()
                }
                held?.let { return 200 to it }
            }
            if (!DemoNetworkRoutes.isDraftsPath(path) || (values.isEmpty() && deleted.isEmpty() && posted == setOf(995006L))) return null
            val name = DemoNetworkRoutes.fixtureName(request.url) ?: return 404 to ""
            val bytes = source.read(name) ?: return 404 to ""
            val doc = Jsoup.parse(demoDraftsPage(bytes, clock).decodeToString())
            if (request.url.queryParameter("page") in listOf(null, "1") && values.containsKey(995007L)) {
                doc.selectFirst("li#work_995001")?.clone()?.let { row ->
                    row.attr("id", "work_995007")
                    row.selectFirst("h4.heading a")?.attr("href", "/works/995007")
                    doc.selectFirst("ol.work.index")?.prependChild(row)
                }
            }
            for ((workId, fields) in values) {
                val row = doc.selectFirst("li#work_$workId") ?: continue
                row.selectFirst("h4.heading a")?.text(fields["work[title]"]?.firstOrNull().orEmpty().ifEmpty { "Untitled" })
                row.selectFirst("blockquote.summary")?.html(fields["work[summary]"]?.firstOrNull().orEmpty())
                row.selectFirst("h5.fandoms")?.let { fandoms ->
                    fandoms.empty()
                    io.github.cidy02.kudos.network.ao3.writing.splitWorkList(fields["work[fandom_string]"]?.firstOrNull().orEmpty())
                        .forEach { fandoms.appendElement("a").addClass("tag").text(it) }
                }
                for ((kind, name) in listOf("rating" to "work[rating_string]", "category" to "work[category_strings][]",
                    "warnings" to "work[archive_warning_strings][]")) {
                    row.selectFirst(".$kind .text")?.text(fields[name].orEmpty().filter { it.isNotEmpty() }.joinToString(", "))
                }
                fields["work[chapter_attributes][content]"]?.firstOrNull()?.let {
                    row.selectFirst("dd.words")?.text(io.github.cidy02.kudos.network.ao3.writing.AO3WordCounter.count(it).toString())
                }
            }
            for (removed in deleted + posted) doc.select("li#work_$removed").remove()
            return 200 to doc.outerHtml()
        }
        if (request.method != "POST" || (path != "/works" && (id == null || path.endsWith("/edit")))) return null
        val workId = id ?: 995007L
        val fixture = when (workId) {
            995001L -> "ao3_demo_work_draft_edit"
            995006L -> "ao3_demo_work_posted_edit"
            else -> "ao3_work_new_draft"
        }
        val html = edited[workId] ?: source.read(fixture)?.decodeToString() ?: return 404 to ""
        val doc = Jsoup.parse(html)
        chapters.applyToWork(doc, workId)
        val buffer = okio.Buffer()
        request.body?.writeTo(buffer)
        val fields = buffer.readUtf8().split('&').filter { it.isNotEmpty() }.map {
            val pair = it.split('=', limit = 2)
            URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
        }.groupBy({ it.first }, { it.second })
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")
        if (fields["_method"] == listOf("delete")) {
            val deleteToken = "demo-delete-$workId=="
            val valid = id != null && fields.keys == setOf("authenticity_token", "_method") &&
                fields["authenticity_token"] == listOf(deleteToken) && request.header("X-CSRF-Token") == deleteToken
            val title = doc.selectFirst("[name='work[title]']")?.attr("value")
            val reason = when {
                !valid -> "AO3 didn't accept the change."
                title == "Refuse this delete" -> "This work could not be deleted."
                else -> null
            }
            if (reason != null) return 422 to "<main id='main'><div class='flash error'>$reason</div></main>"
            deleted += workId
            return 200 to "<main id='main'><div class='flash notice'>Your work was deleted.</div></main>"
        }
        val submits = fields.keys.filter { it in setOf("save_button", "update_button", "post_button", "preview_button", "edit_button", "post_without_preview_button") }
        val submit = submits.singleOrNull()
        val valid = fields["authenticity_token"] == listOf(token) && request.header("X-CSRF-Token") == token &&
            submit != null && fields[submit] == listOf("1") && submit in
            (if (workId in posted) setOf("update_button", "preview_button") else setOf("save_button", "post_button", "preview_button"))
        val reason = when {
            !valid -> "AO3 didn't accept the change."
            fields["work[title]"] == listOf("Refuse this draft") -> "Title is too long (maximum is 255 characters)"
            submit == "post_button" && fields["work[title]"] == listOf("Refuse this post") -> "This draft could not be posted."
            submit == "post_button" && fields["work[title]"].orEmpty().all { it.isBlank() } -> "Title can't be blank"
            submit == "post_button" && fields["work[rating_string]"].orEmpty().all { it.isBlank() } -> "Please select a rating"
            submit == "post_button" && fields["work[archive_warning_strings][]"].orEmpty().all { it.isEmpty() } -> "Please select at least one warning"
            submit == "post_button" && fields["work[fandom_string]"].orEmpty().all { it.isBlank() } -> "Fandom can't be blank"
            submit == "post_button" && fields["work[language_id]"].orEmpty().all { it.isBlank() } -> "Language can't be blank"
            else -> chapters.totalFailure(workId)
        }
        if (reason != null) return 422 to "<main id='main'><form><div id='error'><ul><li>$reason</li></ul></div></form></main>"
        for (control in doc.select("form#work-form [name]")) {
            val sent = fields[control.attr("name")] ?: continue
            when (control.tagName()) {
                "textarea" -> control.text(sent.firstOrNull().orEmpty())
                "select" -> control.select("option").forEach { option ->
                    if (option.attr("value") in sent) option.attr("selected", "selected") else option.removeAttr("selected")
                }
                "input" -> if (control.attr("type") in setOf("checkbox", "radio")) {
                    if (control.attr("value") in sent) control.attr("checked", "checked") else control.removeAttr("checked")
                } else control.attr("value", sent.firstOrNull().orEmpty())
            }
        }
        doc.selectFirst("form#work-form")?.attr("action", "/works/$workId")
        if (id == null) {
            doc.selectFirst("h2.heading")?.text("Edit Work")
            doc.selectFirst("form#work-form")?.prependElement("input")
                ?.attr("type", "hidden")?.attr("name", "_method")?.attr("value", "patch")
        }
        if (submit == "post_button") {
            posted += workId
            doc.select("[name=save_button], [name=post_button]").remove()
            doc.selectFirst("form#work-form")?.appendElement("input")?.attr("type", "submit")?.attr("name", "update_button")?.attr("value", "Update")
        }
        // Existing preview renders the current buffer, but does not save those edits on AO3.
        if (submit != "preview_button" || id == null) {
            edited[workId] = doc.outerHtml()
            values[workId] = fields
        }
        if (submit == "preview_button") {
            val page = Jsoup.parse("<main id='main'><div id='previewpane'><h2 class='title'></h2></div></main>")
            page.head().appendElement("meta").attr("name", "csrf-token").attr("content", token.orEmpty())
            if (id == null) page.selectFirst("#main")?.prependElement("div")?.addClass("flash notice")?.text("Draft was successfully created.")
            val pane = page.selectFirst("#previewpane")!!
            pane.selectFirst("h2.title")?.text(fields["work[title]"]?.firstOrNull().orEmpty().ifEmpty { "Untitled" })
            for ((label, name) in listOf("Summary:" to "work[summary]", "Notes:" to "work[notes]", "" to "work[chapter_attributes][content]", "End notes:" to "work[endnotes]")) {
                val text = fields[name]?.firstOrNull().orEmpty()
                if (text.isEmpty()) continue
                val module = pane.appendElement("div").addClass("module")
                if (label.isNotEmpty()) module.appendElement("h3").addClass("heading").text(label)
                module.appendElement("div").addClass("userstuff").html(text)
            }
            pane.appendElement("form").attr("method", "post").attr("action", "/works/$workId")
                .appendElement("input").attr("name", "edit_button").attr("type", "submit").attr("value", "Edit")
            return 200 to page.outerHtml()
        }
        val notice = when (submit) { "post_button" -> "Work was successfully posted."; "update_button" -> "Work was successfully updated."; else -> "Draft was successfully saved." }
        return 200 to "<main id='main'><div class='flash notice'>$notice</div></main>"
    }
}

/** Original fixture-only new/edit/delete answers. Missing assets and unknown writes never dispatch a socket. */
private class DemoCollectionForms {
    private var edited: String? = null
    private var deleted = false
    private val created = mutableSetOf<String>()

    @Synchronized
    fun answer(request: okhttp3.Request, fixtures: FixtureSource): Pair<Int, String>? {
        val path = DemoNetworkRoutes.decodedPath(request.url).trimEnd('/')
        if (request.method == "GET") {
            // The show page only, which Moderation reads. The collection's own page reads
            // /profile, and keeps the fixture it had (its counts are what that page shows).
            if (path == "/collections/winter_exchange") {
                val source = fixtures.read("ao3_demo_moderation_show") ?: return 404 to ""
                if (deleted) return 404 to ""
                val doc = Jsoup.parse(source.decodeToString())
                val form = edited?.let { Jsoup.parse(it) }
                fun flag(name: String) = form?.select("input[type=checkbox]")?.firstOrNull {
                    it.attr("name") == "collection[collection_preference_attributes][$name]"
                }?.hasAttr("checked") ?: true
                doc.selectFirst("p.type")?.text("(Open, Moderated" +
                    (if (flag("unrevealed")) ", Unrevealed" else "") +
                    (if (flag("anonymous")) ", Anonymous" else "") + ", Gift Exchange Challenge)")
                return 200 to doc.outerHtml()
            }
            if (path == "/collections/lantern_archive" || path == "/collections/refused_name") {
                return if (path.substringAfterLast('/') in created) 200 to "<h2>Original demo collection</h2>" else 404 to ""
            }
            if (path == "/collections/taken_name") return 200 to "<h2>Original occupied demo name</h2>"
            val fixture = when (path) {
                "/collections/new" -> "ao3_demo_collection_new"
                "/collections/winter_exchange/edit" -> if (deleted) return 404 to "" else "ao3_demo_collection_edit"
                "/collections/winter_exchange/confirm_delete" -> if (deleted) return 404 to "" else "ao3_demo_collection_destroy"
                else -> return null
            }
            return fixtures.read(fixture)?.let { bytes ->
                val body = if (fixture.endsWith("_edit")) edited ?: Jsoup.parse(bytes.decodeToString()).apply {
                    select("input[type=checkbox]").firstOrNull {
                        it.attr("name") == "collection[collection_preference_attributes][unrevealed]"
                    }?.attr("checked", "checked")
                }.outerHtml() else bytes.decodeToString()
                200 to body
            }
                ?: (404 to "")
        }
        if (request.method != "POST" || path !in setOf("/collections", "/collections/winter_exchange")) return null
        val buffer = Buffer()
        request.body?.writeTo(buffer)
        val pairs = buffer.readUtf8().split('&').map { part ->
            val pair = part.split('=', limit = 2)
            URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
        }
        val fields = pairs.toMap()
        if (path == "/collections/winter_exchange" && fields["_method"] == "delete") {
            if (fixtures.read("ao3_demo_collection_destroy") == null || deleted ||
                fields["authenticity_token"] != "demo-collection-destroy-token") return refusal()
            deleted = true
            return 200 to "<div class='flash notice'>Collection deleted.</div>"
        }
        val isEdit = path == "/collections/winter_exchange"
        val expected = if (isEdit) "demo-collection-edit-token" else "demo-collection-new-token"
        if (fields["authenticity_token"] != expected || (isEdit && (deleted || fields["_method"] != "patch"))) return refusal()
        val name = fields["collection[name]"].orEmpty()
        val invalid = !isEdit && (name == "refused_name" || name == "taken_name" || name in created)
        val source = fixtures.read(if (invalid) "ao3_demo_collection_invalid" else if (isEdit) "ao3_demo_collection_edit" else "ao3_demo_collection_new")
            ?: return 404 to ""
        val doc = Jsoup.parse(source.decodeToString())
        fields.forEach { (name, value) ->
            doc.select("input, textarea, select").filter { it.attr("name") == name }.forEach { control ->
                when {
                    control.tagName() == "textarea" -> control.text(value)
                    control.tagName() == "select" -> control.select("option").forEach { option ->
                        val selected = if (name == "owner_pseuds[]") pairs.filter { it.first == name }.map { it.second }
                            else listOf(value)
                        option.removeAttr("selected"); if (option.attr("value") in selected) option.attr("selected", "selected")
                    }
                    control.attr("type") == "checkbox" -> {
                        control.removeAttr("checked"); if (value == "1") control.attr("checked", "checked")
                    }
                    else -> control.attr("value", value)
                }
            }
        }
        if (invalid) return 422 to doc.outerHtml()
        if (isEdit) edited = doc.outerHtml() else created.add(name)
        doc.selectFirst("#main")!!.prepend("<div class='flash notice'>Collection was successfully ${if (isEdit) "updated" else "created"}.</div>")
        return 200 to doc.outerHtml()
    }

    private fun refusal() = 422 to "<div class='flash error'>AO3 couldn't save the collection.</div>"
}

/** Reuse the existing collection answers, identically in the HTTP and browser demo paths. */
private fun demoChallengeCollectionPage(bytes: ByteArray, path: String): ByteArray = when (path) {
    "/collections/rare_pairs", "/collections/rare_pairs/profile" -> bytes.decodeToString()
        .replace("winter_exchange", "rare_pairs").replace("Winter Exchange 2026", "Rare Pairs Week").encodeToByteArray()
    "/collections/summer_meme", "/collections/summer_meme/profile" -> bytes.decodeToString()
        .replace("winter_exchange", "summer_meme").replace("Winter Exchange 2026", "Summer Prompt Meme")
        .replace("Gift Exchange", "Prompt Meme").replace("gift_exchange", "prompt_meme")
        .replace("Winter Exchange Tags", "Summer Prompt Tags")
        .replace("/tag_sets/42", "/tag_sets/44")
        .replace("      <li><a href=\"/tag_sets/43\">Snowbound Characters</a></li>\n", "")
        .replace("Sign-ups are open until February.", "Leave a summer prompt about an imaginary seaside town.")
        .encodeToByteArray()
    else -> bytes
}

/** One participant server page per collection, shared by membership decisions, invitation and leaving. */
private class DemoCollectionParticipants {
    private val pages = mutableMapOf<String, String>()

    @Synchronized
    fun answer(request: okhttp3.Request, fixtures: FixtureSource): Pair<Int, String>? {
        val path = DemoNetworkRoutes.decodedPath(request.url).trimEnd('/')
        val slug = request.url.pathSegments.getOrNull(1) ?: return null
        if (slug !in setOf("winter_exchange", "rare_pairs") || !path.startsWith("/collections/")) return null
        val root = "/collections/$slug"
        val participants = "$root/participants"
        // Winter's show stays with DemoCollectionForms so reveal/deletion mutations still work.
        if (slug == "rare_pairs" && request.method == "GET" && path in setOf(root, "$root/profile")) {
            val source = fixtures.read("ao3_demo_maintainers_show") ?: return 404 to ""
            return 200 to demoChallengeCollectionPage(source, path).decodeToString()
        }
        if (path != participants && !path.startsWith("$participants/")) return null
        val source = fixtures.read(if (slug == "winter_exchange") "ao3_demo_moderation_participants" else "ao3_demo_maintainers_last_owner")
            ?: return 404 to ""
        val doc = Jsoup.parse(pages[slug] ?: source.decodeToString())
        if (request.method == "GET" && path == participants) return 200 to doc.outerHtml()
        if (request.method != "POST") return 405 to ""
        val buffer = Buffer()
        request.body?.writeTo(buffer)
        val fields = buffer.readUtf8().split('&').associate { part ->
            val pair = part.split('=', limit = 2)
            URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
        }
        fun refusal(message: String): Pair<Int, String> {
            val error = org.jsoup.nodes.Element("div").addClass("flash").addClass("error").text(message)
            return 422 to (error.outerHtml() + "<div class='error'><p>${error.html()}</p></div>")
        }
        if (path == "$participants/add") {
            if (fields.keys != setOf("authenticity_token", "participants_to_invite") ||
                fields["authenticity_token"] != "demo-participants-token") return refusal("AO3 couldn't invite that maintainer.")
            val name = fields["participants_to_invite"].orEmpty()
            if (name != "lanternkeeper") return refusal("We couldn't find an account named $name.")
            if (doc.select("li[id^=participant_]").any { it.selectFirst("span.byline a")?.text() == name })
                return refusal("That account has already been invited.")
            val row = doc.selectFirst("ul.participant.index")!!.appendElement("li").attr("id", "participant_109")
            row.appendElement("span").addClass("byline").appendElement("a").attr("href", "/users/$name").text(name)
            row.appendElement("form").attr("action", "$participants/109").attr("method", "post")
                .appendElement("select").attr("name", "collection_participant[participant_role]")
                .appendElement("option").attr("value", "Invited").attr("selected", "selected").text("Invited")
            pages[slug] = doc.outerHtml()
            return 200 to "<div class='flash notice'>Invitation sent.</div>"
        }
        if (path == "$participants/101") {
            val showSource = fixtures.read(if (slug == "winter_exchange") "ao3_demo_moderation_show" else "ao3_demo_maintainers_show")
                ?: return 404 to ""
            val token = Jsoup.parse(showSource.decodeToString()).selectFirst("meta[name=csrf-token]")?.attr("content")
            if (token.isNullOrEmpty() || fields != mapOf("_method" to "delete", "authenticity_token" to token))
                return refusal("AO3 couldn't leave that collection.")
            val owners = doc.select("li[id^=participant_]").count { it.selectFirst("option[selected]")?.attr("value") == "Owner" }
            if (owners <= 1) return refusal("You're the last owner. Appoint another owner before you step down.")
            val reader = doc.selectFirst("#participant_101") ?: return refusal("AO3 couldn't leave that collection.")
            reader.remove()
            pages[slug] = doc.outerHtml()
            return 200 to "<div class='flash notice'>You have left the collection.</div>"
        }
        val id = request.url.pathSegments.lastOrNull()?.toIntOrNull()
        val row = doc.getElementById("participant_$id")
        val accept = fields == mapOf("_method" to "patch", "authenticity_token" to "demo-participants-token",
            "collection_participant[participant_role]" to "Member")
        val decline = fields == mapOf("_method" to "delete", "authenticity_token" to "demo-participants-token")
        if (slug != "winter_exchange" || id !in setOf(105, 106) || row == null ||
            row.selectFirst("option[selected]")?.attr("value") != "None" || (!accept && !decline))
            return refusal("That membership request could not be changed.")
        if (accept) row.select("option").forEach {
            it.removeAttr("selected"); if (it.attr("value") == "Member") it.attr("selected", "selected")
        } else row.remove()
        pages[slug] = doc.outerHtml()
        return 200 to "<div class='flash notice'>Membership request updated.</div>"
    }
}

internal fun OkHttpClient.Builder.installDemoNetworkBlock(): OkHttpClient.Builder =
    addInterceptor(DemoNetworkInterceptor())

/** Mutable local server state is owned by the interceptor, never by production account models. */
private class DemoCollectionItems(private val account: Boolean = false) {
    private val changes = mutableMapOf<String, String>()
    private val removed = mutableSetOf<String>()

    @Synchronized
    fun answer(request: okhttp3.Request, fixture: ByteArray?): Pair<Int, String> {
        if (fixture == null) return 404 to ""
        val doc = Jsoup.parse(fixture.decodeToString())
        val rows = doc.select("li.collection.item")
        if (request.method == "POST") {
            val buffer = Buffer()
            request.body?.writeTo(buffer)
            val fields = buffer.readUtf8().split('&').associate { field ->
                val parts = field.split('=', limit = 2)
                URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts.getOrElse(1) { "" }, "UTF-8")
            }
            val edits = fields.filterKeys { it.startsWith("collection_items[") }
            val ids = edits.keys.mapNotNull { Regex("^collection_items\\[(\\d+)]").find(it)?.groupValues?.get(1) }.distinct()
            val id = ids.singleOrNull()
            val row = rows.firstOrNull { it.selectFirst("h4.heading")?.id() == "collection_item_$id" }
            val controls = row?.select("input, select").orEmpty()
            val endpointMatches = if (account) Regex("^/users/[^/]+/collection_items/update_multiple/?$")
                .matches(DemoNetworkRoutes.decodedPath(request.url)) else
                request.url.encodedPath == "/collections/winter_exchange/items/update_multiple"
            val accepted = endpointMatches && fields["_method"] == "patch" &&
                fields["authenticity_token"] == (if (account) "demo-user-items-token" else "demo-items-token") &&
                id != null && id !in removed && row != null && !row.hasAttr("data-refuse") && edits.isNotEmpty() &&
                edits.all { (name, value) ->
                    val control = controls.firstOrNull { it.attr("name") == name && it.attr("type") != "hidden" }
                    control != null && !control.hasAttr("disabled") &&
                        (if (control.tagName() == "select") control.select("option").any { it.attr("value") == value }
                        else value in setOf("0", "1"))
                }
            if (!accepted) return 422 to "<div class='flash error'>AO3 couldn't update that collection item.</div>"
            changes.putAll(edits)
            if (edits["collection_items[$id][remove]"] == "1") removed.add(id!!)
            return 200 to "<div class='flash notice'>Collection item updated.</div>"
        }
        if (request.method != "GET") return 405 to ""
        rows.forEach { row ->
            val id = row.selectFirst("h4.heading")!!.id().removePrefix("collection_item_")
            row.select("select, input[type=checkbox]").forEach { control ->
                changes[control.attr("name")]?.let { value ->
                    if (control.tagName() == "select") control.select("option").forEach { option ->
                        option.removeAttr("selected")
                        if (option.attr("value") == value) option.attr("selected", "selected")
                    } else {
                        control.removeAttr("checked")
                        if (value == "1") control.attr("checked", "checked")
                    }
                }
            }
            fun approval(suffix: String): String = row.select("select").firstOrNull {
                it.attr("name").endsWith("[$suffix]")
            }?.selectFirst("option[selected]")?.attr("value").orEmpty()
            val creator = approval("user_approval_status")
            val moderator = approval("collection_approval_status")
            val matches = when (request.url.queryParameter("status")) {
                "unreviewed_by_user" -> creator == "unreviewed"
                "unreviewed_by_collection" -> moderator == "unreviewed" && (!account || creator == "approved")
                "rejected_by_collection" -> moderator == "rejected"
                "approved" -> creator == "approved" && moderator == "approved"
                else -> if (account) creator == "unreviewed" else moderator == "unreviewed"
            }
            if (id in removed || !matches) row.remove()
        }
        val remaining = doc.select("li.collection.item")
        val total = maxOf(1, (remaining.size + 2) / 3)
        val page = (request.url.queryParameter("page")?.toIntOrNull() ?: 1).coerceAtLeast(1)
        remaining.forEachIndexed { index, row -> if (index / 3 + 1 != page) row.remove() }
        val main = doc.selectFirst("#main")!!
        if (doc.select("li.collection.item").isEmpty()) main.append("<p class='note'>No items found.</p>")
        if (total > 1) main.append("<ol class='pagination'>" + (1..total).joinToString("") {
            "<li><a href='?page=$it'>$it</a></li>"
        } + "</ol>")
        return 200 to doc.outerHtml()
    }
}

/** Only the two tag-set 42 write addresses; process-local server state resets on relaunch. */
private class DemoTagSetWrites {
    private val additions = mutableMapOf<String, List<String>>()
    private val rejected = mutableSetOf<String>()

    @Synchronized
    fun answer(request: okhttp3.Request, source: FixtureSource): Pair<Int, String>? {
        val path = DemoNetworkRoutes.decodedPath(request.url).trimEnd('/')
        if (path !in setOf("/tag_sets/42", "/tag_sets/42/edit", "/tag_sets/42/nominations")) return null
        if (request.method !in setOf("GET", "POST") || (request.method != "GET" && path.endsWith("edit"))) return null
        val name = DemoNetworkRoutes.fixtureName(request.url) ?: return 404 to ""
        val raw = source.read(name)?.decodeToString() ?: return 404 to ""
        if (request.method == "GET") {
            if (additions.isEmpty() && rejected.isEmpty()) return 200 to raw
            val doc = Jsoup.parse(raw)
            if (path.endsWith("nominations")) {
                doc.select("li.nomination, tr.nomination, div.nomination").forEach { row ->
                    if (row.selectFirst(".tag")?.text() in rejected) row.textNodes().forEach {
                        it.text(it.text().replace("unreviewed", "rejected"))
                    }
                }
                doc.select("input[name]").forEach { input ->
                    val key = input.attr("name")
                    val tag = key.substringAfter("_change_", "").replace("#LBRACKET", "[").replace("#RBRACKET", "]")
                    if (tag in rejected) input.attr("name", key.replace("_change_", "_reject_"))
                }
            } else {
                val categories = listOf("fandom" to "Fandoms", "character" to "Characters",
                    "relationship" to "Relationships", "freeform" to "Additional tags")
                categories.forEach { (field, label) ->
                    val heading = doc.select("h3.heading").firstOrNull { it.text().startsWith(label) }
                    val count = heading?.text()?.filter(Char::isDigit)?.toIntOrNull() ?: 0
                    heading?.text("$label (${count + additions[field].orEmpty().size})")
                }
            }
            return 200 to doc.outerHtml()
        }
        if (request.method != "POST") return null
        val buffer = Buffer()
        request.body?.writeTo(buffer)
        val fields = buffer.readUtf8().split('&').associate { encoded ->
            val parts = encoded.split('=', limit = 2)
            URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts.getOrElse(1) { "" }, "UTF-8")
        }
        fun refused(message: String) = 422 to "<div class='flash error'>$message</div>"
        val token = if (path.endsWith("nominations")) "demo-tag-set-42-nominations" else "demo-tag-set-42"
        if (fields["authenticity_token"] != token || fields["_method"] != "put") return refused("The tag-set form could not be verified.")
        if (path.endsWith("nominations")) {
            val key = fields.keys.singleOrNull { "_reject_" in it } ?: return refused("No nomination was selected.")
            if (fields.size != 3 || fields[key] != "1") return refused("The nomination fields were not accepted.")
            when (key) {
                "fandom_reject_Paper Harbor" -> return refused("Paper Harbor is locked for this review.")
                "freeform_reject_Letters #LBRACKETWinter#RBRACKET" -> rejected += "Letters [Winter]"
                else -> return refused("That nomination was not accepted.")
            }
        } else {
            val labels = linkedMapOf("fandom" to "Fandom tags to add", "character" to "Character tags to add",
                "relationship" to "Relationship tags to add", "freeform" to "Additional tags to add")
            val keys = labels.keys.map { "owned_tag_set[tag_set_attributes][${it}_tagnames_to_add]" }
            if (fields.keys != (keys + listOf("authenticity_token", "_method")).toSet()) return refused("The tag lists were not accepted.")
            labels.forEach { (field, label) ->
                val value = fields.getValue("owned_tag_set[tag_set_attributes][${field}_tagnames_to_add]")
                if (value.split(',').any { it.trim().equals("Uncharted Lantern", ignoreCase = true) })
                    return refused("$label: Uncharted Lantern could not be added.")
            }
            labels.keys.forEach { field ->
                val tags = fields.getValue("owned_tag_set[tag_set_attributes][${field}_tagnames_to_add]")
                    .split(',').map(String::trim).filter(String::isNotEmpty)
                additions[field] = (additions[field].orEmpty() + tags).distinct()
            }
        }
        return 200 to "<div class='flash notice'>Tag set updated.</div>"
    }
}

/** Summer's local claim state belongs to this interceptor and resets with the app process. */
private class DemoPromptMemeWrites {
    private val ownClaims = mutableMapOf(702 to 801)
    private val changed = mutableSetOf<Int>()
    private val base = "/collections/summer_meme"

    @Synchronized
    fun answer(request: okhttp3.Request, source: FixtureSource): Pair<Int, String>? {
        val path = DemoNetworkRoutes.decodedPath(request.url).trimEnd('/')
        if (path != "$base/requests" && path != "$base/claims" && !path.startsWith("$base/claims/")) return null
        val page = if (path == "$base/requests") request.url.queryParameter("page") ?: "1" else "1"
        if (page !in setOf("1", "2")) return 404 to ""
        val raw = source.read("ao3_demo_meme_requests_$page")?.decodeToString() ?: return 404 to ""
        val doc = Jsoup.parse(raw)
        fun promptID(row: org.jsoup.nodes.Element): Int? =
            row.selectFirst("a[href*='/prompts/']")?.attr("href")?.substringAfterLast('/')?.toIntOrNull()
                ?: row.selectFirst("form[action*='/claims']")?.attr("action")?.substringAfter("prompt_id=")?.toIntOrNull()
        if (request.method == "GET") {
            if (path == "$base/requests" && changed.isEmpty()) return 200 to raw
            if (path != "$base/requests" && (path != "$base/claims" || request.url.queryParameter("for_user") != "true"))
                return 404 to ""
            doc.select("ul.prompt.index > li.blurb").forEach { row ->
                val id = promptID(row)
                if (id in changed) {
                    row.select("form[action*='/claims'], a[data-method=delete]").remove()
                    row.select("div.claims li").filter { it.text() == "AO3_Reader" }.forEach { it.remove() }
                    if (row.selectFirst("div.claims ul")?.text().isNullOrBlank()) row.select("div.claims").remove()
                    val claim = ownClaims[id]
                    if (claim != null) {
                        val list = row.selectFirst("div.claims ul") ?: row.appendElement("div").addClass("claims").appendElement("ul")
                        list.appendElement("li").text("AO3_Reader")
                        row.appendElement("a").attr("href", "$base/claims/$claim").attr("data-method", "delete").text("Drop Claim")
                    } else row.appendElement("form").attr("action", "$base/claims?prompt_id=$id").attr("method", "post")
                        .appendElement("input").attr("type", "submit").attr("value", "Claim")
                }
                if (path == "$base/claims" && id !in ownClaims) row.remove()
            }
            if (path == "$base/claims") {
                doc.selectFirst("meta[name=csrf-token]")?.attr("content", "demo-meme-claims")
                doc.selectFirst("h2.heading")?.text("Your claims for Summer Prompt Meme")
                doc.select("ol.pagination").remove()
            }
            return 200 to doc.outerHtml()
        }
        if (request.method != "POST" || path == "$base/requests") return 405 to ""
        val buffer = Buffer()
        request.body?.writeTo(buffer)
        val fields = buffer.readUtf8().split('&').associate { encoded ->
            val parts = encoded.split('=', limit = 2)
            URLDecoder.decode(parts[0], "UTF-8") to URLDecoder.decode(parts.getOrElse(1) { "" }, "UTF-8")
        }
        fun refusal(message: String) = 422 to "<div class='flash error'>$message</div>"
        if (path == "$base/claims") {
            val id = fields["prompt_id"]?.toIntOrNull() ?: return refusal("AO3 couldn't claim that prompt.")
            if (fields != mapOf("authenticity_token" to "demo-meme-requests", "prompt_id" to id.toString()) ||
                id !in setOf(701, 702, 704, 705, 706) || id in ownClaims) return refusal("AO3 couldn't claim that prompt.")
            if (id == 704) return refusal("This prompt is closed to new claims.")
            ownClaims[id] = 1000 + id
            changed += id
            return 200 to "<div class='flash notice'>Prompt claimed.</div>"
        }
        val claim = path.substringAfterLast('/').toIntOrNull()
        val id = ownClaims.entries.firstOrNull { it.value == claim }?.key
        if (fields != mapOf("_method" to "delete", "authenticity_token" to "demo-meme-claims") || id == null)
            return refusal("AO3 couldn't release that prompt.")
        ownClaims.remove(id)
        changed += id
        return 200 to "<div class='flash notice'>Claim released.</div>"
    }
}

/** One local form per address. All mutations die with the interceptor/process. */
private class DemoChallengeSignUps {
    private val saved = mutableMapOf<String, String>()
    private val withdrawn = mutableSetOf<Int>()

    @Synchronized
    fun answer(request: okhttp3.Request, source: FixtureSource): Pair<Int, String>? {
        val path = DemoNetworkRoutes.decodedPath(request.url).trimEnd('/')
        val slug = request.url.pathSegments.getOrNull(1) ?: return null
        if (slug !in setOf("winter_exchange", "summer_meme") ||
            !path.startsWith("/collections/$slug/signups")) return null
        val base = "/collections/$slug/signups"
        if (request.method == "GET") {
            if (slug == "winter_exchange" && path == base) {
                val fixture = DemoNetworkRoutes.fixtureName(request.url) ?: return 404 to ""
                val raw = source.read(fixture)?.decodeToString() ?: return 404 to ""
                val doc = Jsoup.parse(raw)
                doc.select("dl.index > dt.participant").filter { heading -> withdrawn.any { id ->
                    heading.selectFirst("a")?.attr("href") == "$base/$id"
                } }.forEach { heading -> heading.nextElementSibling()?.remove(); heading.remove() }
                return 200 to if (withdrawn.isEmpty()) raw else doc.outerHtml()
            }
            if (slug == "winter_exchange" && path in setOf("$base/4/confirm_delete", "$base/5/confirm_delete", "$base/5/edit")) {
                val fixture = DemoNetworkRoutes.fixtureName(request.url) ?: return 404 to ""
                return 200 to (source.read(fixture)?.decodeToString() ?: return 404 to "")
            }
            if (path !in setOf("$base/new", "$base/4/edit")) return if (path == base) null else 404 to ""
            if (path == "$base/4/edit" && 4 in withdrawn) return 404 to ""
            saved[slug]?.let { return 200 to it }
            val fixture = DemoNetworkRoutes.fixtureName(request.url) ?: return 404 to ""
            return 200 to (source.read(fixture)?.decodeToString() ?: return 404 to "")
        }
        if (request.method != "POST" || path !in setOf(base, "$base/4", "$base/5")) return 405 to ""
        val buffer = Buffer()
        request.body?.writeTo(buffer)
        val fields = buffer.readUtf8().split('&').map { encoded ->
            val pair = encoded.split('=', limit = 2)
            URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
        }
        val override = fields.lastOrNull { it.first == "_method" }?.second
        if (override == "delete" && slug == "winter_exchange" && path in setOf("$base/4", "$base/5")) {
            val id = path.substringAfterLast('/').toInt()
            val confirm = source.read("ao3_demo_signup_${id}_confirm_delete")?.decodeToString() ?: return 404 to ""
            val token = Jsoup.parse(confirm).selectFirst("meta[name=csrf-token]")?.attr("content") ?: return 404 to ""
            if (fields != listOf("_method" to "delete", "authenticity_token" to token)) return 422 to "<div class='flash error'>Invalid withdrawal fields.</div>"
            val fixture = if (id == 5) "ao3_demo_signup_withdraw_refused" else "ao3_demo_signup_withdrawn"
            val body = source.read(fixture)?.decodeToString() ?: return 404 to ""
            if (id == 4) { withdrawn += id; saved.remove(slug) }
            return (if (id == 5) 422 else 200) to body
        }
        if (override != if (path == "$base/4") "put" else null) return 405 to ""
        val fixture = if (slug == "summer_meme") "ao3_demo_signup_summer_new"
            else if (path == "$base/4") "ao3_demo_signup_winter_edit" else "ao3_demo_signup_winter_new"
        val raw = saved[slug] ?: source.read(fixture)?.decodeToString() ?: return 404 to ""
        val doc = Jsoup.parse(raw)
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")
        if (fields.lastOrNull { it.first == "authenticity_token" }?.second != token)
            return 422 to "<div class='flash error'>Couldn't prepare the request. Try again, or open the work on AO3.</div>"
        val form = doc.selectFirst("form[action*='/signups']") ?: return 404 to ""
        // Echo modeled posted values in the response; unknown controls stay as served.
        for ((name, value) in fields) {
            val controls = form.select("input, textarea, select").filter { it.attr("name") == name }
            if (controls.isEmpty() && name.startsWith("challenge_signup[")) {
                val flag = Regex("\\[(?:anonymous|any_fandom|any_character|any_relationship|any_freeform|_destroy)]$").containsMatchIn(name)
                when {
                    name.endsWith("[description]") -> form.appendElement("textarea").attr("name", name).text(value)
                    flag -> {
                        form.appendElement("input").attr("type", "hidden").attr("name", name).attr("value", "0")
                        val box = form.appendElement("input").attr("type", "checkbox").attr("name", name).attr("value", "1")
                        if (value == "1") box.attr("checked", "checked")
                    }
                    else -> form.appendElement("input").attr("type", "hidden").attr("name", name).attr("value", value)
                }
            }
            controls.forEach { control ->
                when {
                    control.tagName() == "textarea" -> control.text(value)
                    control.attr("type") == "checkbox" -> {
                        if (value == control.attr("value")) control.attr("checked", "checked") else control.removeAttr("checked")
                    }
                    control.tagName() == "input" && control.attr("type") != "hidden" -> control.attr("value", value)
                }
            }
        }
        if (fields.any { it.first.endsWith("[description]") && it.second.contains("Uncharted Lantern", true) }) {
            val error = source.read("ao3_demo_signup_refused")?.decodeToString() ?: return 404 to ""
            doc.body().prepend(Jsoup.parse(error).body().html())
            return 422 to doc.outerHtml() // no saved state changed
        }
        form.attr("action", "$base/4")
        if (form.selectFirst("input[name=_method]") == null)
            form.appendElement("input").attr("type", "hidden").attr("name", "_method").attr("value", "put")
        for (kind in listOf("requests", "offers")) {
            val indices = fields.mapNotNull { Regex("^challenge_signup\\[${kind}_attributes]\\[([0-9]+)]")
                .find(it.first)?.groupValues?.get(1)?.toIntOrNull() }.distinct()
            for (index in indices) {
                val name = "challenge_signup[${kind}_attributes][$index][id]"
                if (form.select("input").none { it.attr("name") == name })
                    form.appendElement("input").attr("type", "hidden").attr("name", name).attr("value", (100 + index + if (kind == "offers") 10 else 0).toString())
            }
        }
        saved[slug] = doc.outerHtml()
        val notice = source.read("ao3_demo_signup_saved")?.decodeToString() ?: return 404 to ""
        doc.body().prepend(Jsoup.parse(notice).body().html())
        return 200 to doc.outerHtml()
    }
}

/** The demo author's existing Dawn Cycle, with process-local form and sortable answers. */
private class DemoSeriesWrites {
    private var edited: String? = null
    private var managed: String? = null

    @Synchronized
    fun answer(request: okhttp3.Request, source: FixtureSource): Pair<Int, String>? {
        val path = DemoNetworkRoutes.decodedPath(request.url).trimEnd('/')
        if (path !in setOf("/series/321/edit", "/series/321/manage", "/series/321", "/series/321/update_positions") &&
            !Regex("^/serial_works/321[123]$").matches(path)) return null
        if (request.method == "GET") return when (path) {
            "/series/321/edit" -> 200 to (edited ?: source.read("ao3_demo_series_edit")?.decodeToString() ?: return 404 to "")
            "/series/321/manage" -> 200 to (managed ?: source.read("ao3_demo_series_manage")?.decodeToString() ?: return 404 to "")
            else -> null
        }
        if (request.method != "POST") return 405 to ""
        val buffer = okio.Buffer()
        request.body?.writeTo(buffer)
        val fields = buffer.readUtf8().split('&').filter(String::isNotEmpty).map {
            val pair = it.split('=', limit = 2)
            URLDecoder.decode(pair[0], "UTF-8") to URLDecoder.decode(pair.getOrElse(1) { "" }, "UTF-8")
        }.groupBy({ it.first }, { it.second })
        fun refused(reason: String) = 422 to "<main id='main'><div id='error'><ul><li>$reason</li></ul></div></main>"
        if (path == "/series/321") {
            val html = edited ?: source.read("ao3_demo_series_edit")?.decodeToString() ?: return 404 to ""
            val doc = Jsoup.parse(html)
            val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")
            if (fields["authenticity_token"] != listOf(token) || request.header("X-CSRF-Token") != token ||
                request.header("Referer") != "https://archiveofourown.org/series/321" || fields["_method"] != listOf("put"))
                return refused("AO3 didn't accept the change.")
            if (fields["series[title]"] == listOf("Refuse this series")) return refused("Title is too long (maximum is 255 characters)")
            for (control in doc.select("form.series [name]")) {
                val name = control.attr("name")
                // Model the edited fields; retain the original unknown/duplicate controls verbatim.
                if (name !in setOf("series[title]", "series[summary]", "series[series_notes]", "series[complete]",
                        "series[author_attributes][ids][]", "series[author_attributes][byline]")) continue
                val values = fields[name] ?: continue
                when (control.tagName()) {
                    "textarea" -> control.text(values.firstOrNull().orEmpty())
                    "select" -> control.select("option").forEach { option ->
                        if (option.attr("value") in values) option.attr("selected", "selected") else option.removeAttr("selected")
                    }
                    "input" -> if (control.attr("type") == "checkbox") {
                        if (control.attr("value") in values) control.attr("checked", "checked") else control.removeAttr("checked")
                    } else control.attr("value", values.firstOrNull().orEmpty())
                }
            }
            edited = doc.outerHtml()
            return 200 to "<main id='main'><div class='flash notice'>Series was successfully updated.</div></main>"
        }
        val html = managed ?: source.read("ao3_demo_series_manage")?.decodeToString() ?: return 404 to ""
        val doc = Jsoup.parse(html)
        val token = doc.selectFirst("meta[name=csrf-token]")?.attr("content")
        if (fields["authenticity_token"] != listOf(token) || request.header("X-CSRF-Token") != token ||
            request.header("Referer") != "https://archiveofourown.org/series/321/manage") return refused("AO3 didn't accept the change.")
        val list = doc.selectFirst("#sortable_series_list") ?: return 404 to ""
        val rows = list.select("li").associateBy { it.id().removePrefix("serial_") }
        if (path == "/series/321/update_positions") {
            val order = fields["serial[]"].orEmpty()
            if (order.size != rows.size || order.toSet() != rows.keys || fields.containsKey("_method"))
                return refused("The series changed on AO3 since this screen opened. Reopen it and try again.")
            list.empty()
            order.forEach { list.appendChild(rows.getValue(it)) }
        } else {
            val id = path.substringAfterLast('/')
            if (fields["_method"] != listOf("delete") || id !in rows || rows.size <= 1)
                return refused("It is the series' last work on AO3, and AO3 deletes a series with its last work.")
            rows.getValue(id).remove()
        }
        list.select("li").forEachIndexed { index, li -> li.selectFirst("[id^=position-for-]")?.text((index + 1).toString()) }
        managed = doc.outerHtml()
        return 302 to ""
    }
}
