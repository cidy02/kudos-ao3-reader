package io.github.cidy02.kudos.account

import io.github.cidy02.kudos.auth.AO3AuthRepository
import io.github.cidy02.kudos.auth.isSignedIn
import io.github.cidy02.kudos.network.ao3.AO3Client
import io.github.cidy02.kudos.network.ao3.AO3Constants
import io.github.cidy02.kudos.network.ao3.AO3Error
import io.github.cidy02.kudos.network.ao3.AO3Result
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemTab
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsPage
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionItemsUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionModeration
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipantsParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionPeoplePage
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionShow
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipant
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionParticipantsUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionForm
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormParser
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionFormUrls
import io.github.cidy02.kudos.network.ao3.account.AO3CollectionNameAvailability
import io.github.cidy02.kudos.network.ao3.account.collectionNameFormatIsValid
import io.github.cidy02.kudos.network.ao3.account.reservedCollectionNames
import io.github.cidy02.kudos.network.ao3.search.AO3SearchPage
import io.github.cidy02.kudos.network.ao3.search.AO3SearchParser
import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemePage
import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemeParser
import io.github.cidy02.kudos.network.ao3.account.AO3PromptMemeUrls
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeSettings
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeKind
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeSettingsPage
import io.github.cidy02.kudos.network.ao3.account.AO3ChallengeSettingsParser
import io.github.cidy02.kudos.network.ao3.account.ChallengeSettingsDestinations
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetSnapshot
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetParser
import io.github.cidy02.kudos.network.ao3.account.AO3TagSetUrls
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class AO3CollectionDetailRepository(
    private val ao3Client: AO3Client,
    val authRepository: AO3AuthRepository,
    private val collectionParser: AO3CollectionParser = AO3CollectionParser(),
    private val searchParser: AO3SearchParser = AO3SearchParser(),
    /**
     * Where pages are parsed. A parameter so a Compose screen test can keep it on the test
     * thread: the test rule runs effects unconfined, and a load that came back from a pool
     * thread carried on there and wrote the screen's state in the middle of a layout pass.
     * The app's own effects always return to the main thread.
     */
    private val parseDispatcher: CoroutineDispatcher = Dispatchers.Default
) {
    /** iOS: public/base page, then optional edit and nominations for every signed-in viewer. */
    suspend fun getTagSet(id: Int): AO3Result<AO3TagSetSnapshot> {
        val generation = authRepository.generation.value
        val signedIn = authRepository.state.value.isSignedIn
        val parser = AO3TagSetParser()
        fun checkSession() {
            // Session changes must not turn a private load into an anonymous fallback.
            if (generation != authRepository.generation.value) throw CancellationException()
        }
        var loaded = when (val base = fetch(AO3TagSetUrls.page(id), authenticated = signedIn) { parser.parse(it, id) }) {
            is AO3Result.Failure -> return base
            is AO3Result.Success -> base.value
        }
        checkSession()
        if (signedIn) {
            val edit = fetch(AO3TagSetUrls.edit(id)) { parser.parse(it, id) }
            checkSession()
            if (edit is AO3Result.Success) loaded = edit.value
            val queue = fetch(AO3TagSetUrls.nominations(id), parse = parser::parseNominations)
            checkSession()
            if (queue is AO3Result.Success) loaded = loaded.copy(reviewQueue = queue.value)
        }
        return AO3Result.Success(loaded)
    }

    /** Shared 3ba settings-form read only: gift probe, then meme fallback. No profile/tallies. */
    suspend fun getChallengeSettingsForm(slug: String): AO3Result<AO3ChallengeSettings> {
        val generation = authRepository.generation.value
        val parser = AO3ChallengeSettingsParser()
        fun checkSession() {
            if (generation != authRepository.generation.value) throw CancellationException()
        }
        val gift = fetch(ChallengeSettingsDestinations.challengeSettingsEditView(slug, AO3ChallengeKind.GiftExchange)) {
            parser.parseSettings(it, AO3ChallengeKind.GiftExchange)
        }
        checkSession()
        return when (gift) {
            is AO3Result.Success -> gift
            is AO3Result.Failure -> {
                if (gift.error != AO3Error.NotFound && gift.error !is AO3Error.Parse) return gift
                when (val meme = fetch(ChallengeSettingsDestinations.challengeSettingsEditView(slug, AO3ChallengeKind.PromptMeme)) {
                    parser.parseSettings(it, AO3ChallengeKind.PromptMeme)
                }) {
                    is AO3Result.Failure -> return meme
                    is AO3Result.Success -> meme
                }
            }
        }
    }

    /** Exactly one selected prompts page; anonymous only for an already signed-out viewer. */
    suspend fun getPromptMemePrompts(slug: String, page: Int): AO3Result<AO3PromptMemePage> =
        fetch(AO3PromptMemeUrls.requests(slug, page), authenticated = authRepository.state.value.isSignedIn) {
            AO3PromptMemeParser().parse(it, page)
        }

    /** Corrected 3ba: at most four sequential page reads; never read any assignment page. */
    suspend fun getChallengeSettings(slug: String): AO3Result<AO3ChallengeSettingsPage> {
        val generation = authRepository.generation.value
        val parser = AO3ChallengeSettingsParser()
        fun checkSession() {
            if (generation != authRepository.generation.value) throw CancellationException()
        }
        val settings = when (val form = getChallengeSettingsForm(slug)) {
            is AO3Result.Failure -> return form
            is AO3Result.Success -> form.value
        }
        checkSession()
        val tags = when (val result = fetch(ChallengeSettingsDestinations.profile(slug), parse = parser::parseTagSets)) {
            is AO3Result.Success -> result.value
            is AO3Result.Failure -> emptyList()
        }
        checkSession()
        var count: Int? = null
        if (settings.kind == AO3ChallengeKind.GiftExchange) {
            val first = fetch(ChallengeSettingsDestinations.signUpPage(slug)) { parser.parseSignUpCount(it) }
            checkSession()
            if (first is AO3Result.Success) {
                count = if (first.value.totalPages == 1) first.value.count else {
                    val lastPage = first.value.totalPages
                    when (val last = fetch(ChallengeSettingsDestinations.signUpPage(slug, lastPage)) {
                        parser.parseSignUpCount(it, lastPage)
                    }) {
                        is AO3Result.Failure -> null
                        is AO3Result.Success -> first.value.count * (lastPage - 1) + last.value.count
                    }
                }
            }
        }
        checkSession()
        return AO3Result.Success(AO3ChallengeSettingsPage(settings, tags, count))
    }

    /** iOS collectionModeration: items, participants, show; sequential, no profile or prefetch. */
    suspend fun getModeration(slug: String): AO3Result<AO3CollectionModeration> {
        val generation = authRepository.generation.value
        val items = when (val result = getCollectionItems(slug, AO3CollectionItemTab.Unreviewed, 1)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        if (generation != authRepository.generation.value) throw CancellationException()
        val participants = when (val result = getCollectionParticipants(slug)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        if (generation != authRepository.generation.value) throw CancellationException()
        val show = when (val result = fetch(AO3CollectionFormUrls.show(slug)) {
            collectionParser.parseCollectionShow(it, slug)
        }) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        if (generation != authRepository.generation.value) throw CancellationException()
        return AO3Result.Success(AO3CollectionModeration(items, participants.filter { it.isMembershipRequest },
            participants.count { it.isMaintainer }, show.collection.isUnrevealed, show.collection.isAnonymous))
    }

    suspend fun getCollectionParticipants(slug: String): AO3Result<List<AO3CollectionParticipant>> =
        fetch(AO3CollectionParticipantsUrls.page(slug)) {
            AO3CollectionParticipantsParser().parse(it)
        }

    suspend fun getCollectionForm(slug: String?): AO3Result<AO3CollectionForm> =
        fetch(AO3CollectionFormUrls.form(slug)) { AO3CollectionFormParser().parse(it, slug) }

    /** iOS availability probe: anonymous public GET; the shared client owns pacing, slots and retries. */
    suspend fun collectionNameAvailable(name: String): AO3CollectionNameAvailability {
        val trimmed = name.trim()
        if (!collectionNameFormatIsValid(trimmed)) return AO3CollectionNameAvailability.Invalid
        if (trimmed.lowercase() in reservedCollectionNames) return AO3CollectionNameAvailability.Taken
        return when (val result = ao3Client.get(AO3CollectionFormUrls.show(trimmed))) {
            is AO3Result.Success -> when (result.value.statusCode) {
                200 -> AO3CollectionNameAvailability.Taken
                404 -> AO3CollectionNameAvailability.Available
                else -> AO3CollectionNameAvailability.Unknown
            }
            is AO3Result.Failure -> if (result.error == AO3Error.NotFound) AO3CollectionNameAvailability.Available
                else AO3CollectionNameAvailability.Unknown
        }
    }

    suspend fun getCollectionShow(slug: String): AO3Result<AO3CollectionShow> =
        fetch("${AO3Constants.BASE_URL}/collections/$slug/profile") {
            collectionParser.parseCollectionShow(it, slug)
        }

    suspend fun getCollectionWorks(slug: String, page: Int): AO3Result<AO3SearchPage> =
        fetch("${AO3Constants.BASE_URL}/collections/$slug/works?page=$page") {
            searchParser.parseSearchPage(it, page)
        }

    suspend fun getCollectionBookmarks(slug: String, page: Int): AO3Result<AO3SearchPage> =
        fetch("${AO3Constants.BASE_URL}/collections/$slug/bookmarks?page=$page") {
            searchParser.parseWorksListPage(it, page, "li.bookmark.blurb")
        }

    suspend fun getCollectionPeople(slug: String, page: Int): AO3Result<AO3CollectionPeoplePage> =
        fetch("${AO3Constants.BASE_URL}/collections/$slug/people?page=$page") {
            collectionParser.parseCollectionPeoplePage(it, page)
        }

    suspend fun getCollectionItems(
        slug: String,
        tab: AO3CollectionItemTab,
        page: Int
    ): AO3Result<AO3CollectionItemsPage> =
        fetch(AO3CollectionItemsUrls.page(slug, tab, page)) {
            AO3CollectionItemsParser().parse(it, slug, tab, page)
        }

    suspend fun getUserCollectionItems(username: String, tab: AO3CollectionItemTab, page: Int): AO3Result<AO3CollectionItemsPage> {
        val url = AO3CollectionItemsUrls.userPage(username, tab, page)
            ?: return AO3Result.Failure(AO3Error.Parse("AO3 didn't give a collection-items page for this account."))
        return fetch(url) { AO3CollectionItemsParser().parseUser(it, username, tab, page) }
    }

    /** Existing AO3 client read; signed-in by default, public only when explicitly requested. */
    private suspend fun <T> fetch(url: String, authenticated: Boolean = true, parse: (String) -> T): AO3Result<T> {
        currentCoroutineContext().ensureActive()
        val generation = authRepository.generation.value
        val headers = if (!authenticated) emptyMap() else when (val result = authRepository.authenticatedHeaders(url)) {
            is AO3Result.Failure -> return result
            is AO3Result.Success -> result.value
        }
        val result = ao3Client.get(url, headers)
        if (generation != authRepository.generation.value) throw CancellationException()
        return when (result) {
            is AO3Result.Failure -> {
                if (authenticated && result.error == AO3Error.AuthenticationRequired) authRepository.sessionDidExpire(generation)
                result
            }
            is AO3Result.Success -> try {
                AO3Result.Success(withContext(parseDispatcher) {
                    parse(result.value.body)
                })
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                AO3Result.Failure(AO3Error.Parse(e.message ?: "Could not read the collection page."))
            }
        }
    }
}
