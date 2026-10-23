package io.github.cidy02.kudos.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import io.github.cidy02.kudos.BuildConfig
import io.github.cidy02.kudos.network.ao3.DemoNetwork
import io.github.cidy02.kudos.works.WorkDetailSource

internal data class DebugShot(val route: String, val pages: List<String> = emptyList())

/** A82's names, routed through the same pages used by hand. No reads or writes here. */
internal fun debugShot(
    name: String,
    queueId: String,
    collectionId: String,
    workId: String,
    readerId: String
): DebugShot? = when (name) {
    "libpicker" -> DebugShot(Routes.Library, listOf("library", "library-picker"))
    "queuesettings" -> DebugShot(Routes.queueDetail(queueId))
    "newqueue" -> DebugShot(Routes.readingQueues(), listOf("queue-organizer"))
    "editqueue", "addworks", "bulktag" -> DebugShot(Routes.readingQueues(queueId), listOf("queue-page"))
    "queuetag" -> DebugShot(Routes.queueDetail(queueId), listOf("queue-settings"))
    "queuetags" -> DebugShot(Routes.queueDetail(queueId), listOf("queue-settings"))
    "queuetagedit" -> DebugShot(Routes.queueDetail(queueId), listOf("queue-settings", "queue-tag-manager"))
    "addtoqueue", "addtocollection", "downloaddate", "seriespreserve", "bookmarkform" -> DebugShot(
        Routes.workDetail(NavArgCodecs.encodeWorkDetailSource(WorkDetailSource.LocalWork(workId))),
        if (name == "downloaddate") listOf("work-detail", "my-copy") else listOf("work-detail"))
    "queuestorage" -> DebugShot(Routes.QueueStorage)
    "collectiondetails", "collectionreorder" -> DebugShot(Routes.collectionDetail(collectionId), listOf("collection"))
    "newcollection" -> DebugShot(Routes.Collections, listOf("collections"))
    "fandomlist" -> DebugShot(Routes.browseFandoms("TV Shows", "/media/TV Shows/fandoms"))
    "fandomfilter" -> DebugShot(Routes.browseFandoms("TV Shows", "/media/TV Shows/fandoms"), listOf("fandom-list"))
    "fandomworks" -> DebugShot("browse-works/Doctor%20Who")
    "tagworks" -> DebugShot("tag-works/Star%20Wars")
    "savesearch" -> DebugShot(Routes.Search, listOf("search"))
    "languagepicker" -> DebugShot(Routes.Search, listOf("search", "search-filters", "filter-language"))
    "tagpicker" -> DebugShot(Routes.Search, listOf("search", "search-filters", "filter-tags"))
    "pagejump" -> DebugShot("browse-works/Doctor%20Who", listOf("pagination"))
    "readercontents", "readerfind", "readerdisplay", "readerspeech", "readernote" -> DebugShot(Routes.reader(readerId), listOf("reader"))
    "pronunciations" -> DebugShot(Routes.Settings, listOf("settings", "listening-page", "pronunciations"))
    "pronunciationedit" -> DebugShot(Routes.Settings, listOf("settings", "listening-page", "pronunciations", "pronunciation-list"))
    "customizetheme" -> DebugShot(Routes.Settings, listOf("settings", "appearance"))
    "formattingtray" -> DebugShot(Routes.comments(12345, composes = true), listOf("comment-composer"))
    "chapterpicker" -> DebugShot(Routes.comments(12345), listOf("comments"))
    "inboxfilter" -> DebugShot(Routes.AccountInbox, listOf("inbox"))
    "authorabout" -> DebugShot("author-about/AO3_Reader")
    "authorbookmarks" -> DebugShot(Routes.authorProfile("AO3_Reader", io.github.cidy02.kudos.author.AuthorTab.Bookmarks))
    "seriesdetail" -> DebugShot(Routes.seriesWorks("https://archiveofourown.org/series/321"))
    "seriesedit", "seriesreorder" -> DebugShot(Routes.seriesWorks("https://archiveofourown.org/series/321"), listOf("series"))
    "seriesremove" -> DebugShot(Routes.seriesWorks("https://archiveofourown.org/series/321"), listOf("series", "series-editor"))
    "authorworksfilter" -> DebugShot(Routes.authorProfile("AO3_Reader"), listOf("author"))
    "bulkedit" -> DebugShot(Routes.authorProfile("AO3_Reader"), listOf("author"))
    "bulktagstate", "bulknames" -> DebugShot(Routes.authorProfile("AO3_Reader"), listOf("author", "bulk-editor"))
    "colitems" -> DebugShot(Routes.ao3CollectionItems("winter_exchange", "Winter Exchange"))
    "colsfilter" -> DebugShot(Routes.AO3Collections, listOf("ao3-collections"))
    "chsettingsedit" -> DebugShot(Routes.ao3ChallengeSettings("winter_exchange", "Winter Exchange", true), listOf("challenge-settings"))
    // As the collection page opens it: as a maintainer, with the kind it parsed (alone, the list was refused).
    "chsignupdetail" -> DebugShot(Routes.ao3ChallengeSignUps("winter_exchange", "Winter Exchange", true, true,
        io.github.cidy02.kudos.network.ao3.account.AO3ChallengeKind.GiftExchange), listOf("challenge-signups"))
    "prompttags" -> DebugShot(Routes.ao3ChallengeSignUp("winter_exchange", "Winter Exchange"), listOf("challenge-signup"))
    "tagset" -> DebugShot(Routes.ao3TagSet(42, "Winter Exchange Tags", true))
    "tagseteditor" -> DebugShot(Routes.ao3TagSet(42, "Winter Exchange Tags", true), listOf("tag-set"))
    "writingpreview", "chapters", "edittags", "tagseditor", "seriespicker", "collectionsgifts", "creatorspicker", "parentpicker" ->
        DebugShot(Routes.WritingWorkPostedDemo, listOf("work-form"))
    "chapterform" -> DebugShot(Routes.WritingChapterDraftDemo)
    "texteditor" -> DebugShot(Routes.WritingEditorDemo, listOf("text-editor"))
    "recovery" -> DebugShot(Routes.WritingEditorDemo, listOf("text-editor"))
    "prefhelp" -> DebugShot(Routes.AO3Preferences, listOf("preferences"))
    "privacydata" -> DebugShot(Routes.Settings, listOf("settings"))
    "availability" -> DebugShot(Routes.AvailabilitySweep)
    "pairing", "revokedevice" -> DebugShot(Routes.Settings, listOf("settings", "pairing"))
    "backupimport" -> DebugShot(Routes.Backup, listOf("backup"))
    "aboutkudos" -> DebugShot(Routes.About)
    else -> null
}

/** Each mounted page/sheet takes its part once, after its own data is ready. */
internal object DebugShotRequests {
    private var serial = 0
    private data class Request(val serial: Int, val name: String)
    private var pending by mutableStateOf<Map<String, Request>>(emptyMap())

    fun open(name: String, shot: DebugShot) {
        if (BuildConfig.DEBUG && DemoNetwork.isActive) {
            val request = Request(++serial, name)
            pending = shot.pages.associateWith { request }
        }
    }

    fun clear() { pending = emptyMap() }

    @Composable
    fun Read(owner: String, ready: Boolean, open: suspend (String) -> Unit) {
        if (!BuildConfig.DEBUG || !DemoNetwork.isActive) return
        val lifecycle = LocalLifecycleOwner.current.lifecycle
        val request = pending[owner]
        val latestReady by rememberUpdatedState(ready)
        val latestOpen by rememberUpdatedState(open)
        LaunchedEffect(request, lifecycle) {
            if (request != null && pending[owner] == request) {
                // Exiting navigation entries stay composed during the transition; only the new page may take a shot.
                combine(snapshotFlow { latestReady }, lifecycle.currentStateFlow) { readyNow, state ->
                    readyNow && state.isAtLeast(Lifecycle.State.RESUMED)
                }.first { it }
                if (pending[owner] == request) {
                    latestOpen(request.name)
                    if (pending[owner] == request) pending = pending - owner
                }
            }
        }
    }
}

@Composable
internal fun DebugShotEffect(owner: String, ready: Boolean = true, open: suspend (String) -> Unit) {
    DebugShotRequests.Read(owner, ready, open)
}
