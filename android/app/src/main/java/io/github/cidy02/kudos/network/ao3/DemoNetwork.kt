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
    fun webFixture(url: HttpUrl, source: FixtureSource = fixtures): ByteArray? {
        if (!DemoNetworkRoutes.isAo3Host(url.host)) return null
        val path = DemoNetworkRoutes.decodedPath(url).trimEnd('/')
        val name = when (path) {
            "/collections/winter_exchange/participants" -> "ao3_demo_moderation_participants"
            "/collections/winter_exchange" -> "ao3_demo_moderation_show"
            else -> DemoNetworkRoutes.fixtureName(url)
        }
        return name?.let { source.read(it) }
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
        "^/collections/new/?$" to "ao3_demo_collection_new",
        "^/collections/winter_exchange/edit/?$" to "ao3_demo_collection_edit",
        "^/collections/winter_exchange/confirm_delete/?$" to "ao3_demo_collection_destroy",
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
    private val removedSubscriptions = ConcurrentHashMap.newKeySet<String>()
    private val collectionItems = DemoCollectionItems()
    private val userCollectionItems = DemoCollectionItems(account = true)
    private val collectionForms = DemoCollectionForms()
    private val collectionParticipants = DemoCollectionParticipants()

    override fun intercept(chain: Interceptor.Chain): Response {
        if (!isActive()) return chain.proceed(chain.request())
        val url = chain.request().url
        if (!DemoNetworkRoutes.isAo3Host(url.host)) return chain.proceed(chain.request())
        val path = DemoNetworkRoutes.decodedPath(url)
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
        val matchTarget = if (url.queryParameter("show_comments") == "true") "$path/comments" else path
        val name = if (matchTarget == path) DemoNetworkRoutes.fixtureName(url) else DemoNetworkRoutes.fixtureName(matchTarget)
        var bytes = name?.let { fixtures().read(it) }
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
            return 200 to source.decodeToString().replace("winter_exchange", slug)
                .replace("Winter Exchange 2026", "Rare Pairs Week")
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
