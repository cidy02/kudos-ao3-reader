# A49 result: Android 3dh–3ec

Reviewed the requested snapshot, **`0b679d91cc99836623976e15005888992f72e929`**, in `/Users/cidy02/kudos-android-lane`, using `git show` rather than its newer checked-out files. Read the named briefs and followed callers, persistence, navigation, and relevant tests. Reached **all ten items**, in the requested order; no time cutoff. This is a static review: no build, test execution, simulator, sign-in, or AO3 request. Only this report was written; `TASKS.md` was not changed.

Paths below are relative to **`android/app/src/main/java/io/github/cidy02/kudos/`**, unless they start with `android/`. Line numbers and quoted Kotlin refer to the requested commit. P1 means fix before relying on the behavior; P2 means a real fault with a narrower trigger. Timing-dependent findings describe a possible interleaving, not an observed device reproduction.

## 1. 3dm — device speech

### F1 — P2: an installed device engine can be invisible to Kudos

**Evidence.** `reader/speech/AutomaticTTSService.kt:93` creates the platform client:

```kotlin
engine = TextToSpeech(context.applicationContext) { result ->
```

At `:94–95`, any initialization failure leaves no usable voice:

```kotlin
val voice = if (result != TextToSpeech.SUCCESS) null else onDeviceVoice(
    runCatching { engine.voice ?: engine.defaultVoice }.getOrNull(),
```

`android/app/build.gradle.kts:44` says `targetSdk = 37`. The snapshot's `android/app/src/main/AndroidManifest.xml:1–58` has no `<queries>` declaration for the TTS service; none exists elsewhere in the tracked Android manifests. Android's [TextToSpeech API documentation](https://developer.android.com/reference/android/speech/tts/TextToSpeech) calls for that service query when targeting Android 11 or later. The installed SDK's `TtsEngines.java` also confirms engine discovery uses `PackageManager.queryIntentServices`.

**Reader effect.** A reader whose selected offline engine is a separately installed package, without some other visibility grant, can be told to download Kokoro even though their phone already has an offline voice. A preinstalled engine working on the emulator does not cover this case.

**Fix.** Declare the TTS service query. Verify discovery with a separately installed offline engine on Android 11+.

**Confidence: high** about the missing declaration and discovery mechanism; device-dependent whether the chosen engine is already visible.

### F2 — P1: Stop and Pause can happen before a stale job submits its speech

**Evidence.** `reader/speech/AutomaticTTSService.kt:128–135` checks status, then submits outside `handover`:

```kotlin
if (_status.first { it != SpeechStatus.PAUSED } != SpeechStatus.PLAYING) return
val id = "kudos-${utterances.incrementAndGet()}"
val ended = CompletableDeferred<Boolean>()
utterance = id to ended
_spokenText.value = chunks[index]
if (engine.speak(chunks[index], TextToSpeech.QUEUE_FLUSH, null, id) != TextToSpeech.SUCCESS) return
```

At `:158–167`, Stop changes state and stops whatever the engine has **at that moment**:

```kotlin
if (_status.value != SpeechStatus.UNAVAILABLE) _status.value = SpeechStatus.STOPPED
_spokenText.value = ""
cutOff()
// ...
utterance?.second?.complete(false)
engine.stop()
```

The `finally` at `:139–143` clears the bookkeeping but never stops the engine. `reader/speech/ReaderSpeechController.kt:161–162` cancels without joining, and runs speech on `Dispatchers.Default`:

```kotlin
currentSpeakJob?.cancel()
currentSpeakJob = scope.launch(Dispatchers.Default) {
```

**Reader effect.** The speech job passes line 128 and is descheduled. The reader presses Stop; cancellation and `engine.stop()` complete. The old job resumes, sets `utterance`, and calls `engine.speak` before its next cancellable suspension. Its cancelled `await()` exits and clears the record, but the newly submitted audio keeps reading with the player stopped. Pause has the corresponding window: `cutOff()` runs before submission, then the job starts audible speech while state is PAUSED. The lock protects the generation counter and cleanup, not this submission window.

**Fix.** Serialize submission with pause/stop and ownership checks; cancellation of the owning reading must stop its submitted utterance. Test by stopping/pausing precisely between the status check and engine submission, and by overlapping skip jobs.

**Confidence: high** from the interleaving; not reproduced on hardware. The new service test covers an orderly pause after speech has started, not this race.

### F3 — P1: downloading the pack changes control ownership while the device is still speaking

**Evidence.** `reader/speech/AutomaticTTSService.kt:36,47–49` selects an engine anew for every operation:

```kotlin
private fun active(): TTSService = if (packInstalled()) kokoro else device
override suspend fun speak(text: String) = active().speak(text)
override fun pause() = active().pause()
override fun resume() = active().resume()
```

`reader/speech/ReaderSpeechController.kt:105–108` overwrites the player's status when the download finishes:

```kotlin
} else if (info != null && info.state.isFinished) {
    _downloadProgress.value = null
    if (TTSDownloadWorker.isModelDownloaded(appContext)) {
        _status.value = SpeechStatus.STOPPED
```

Cancellation of `SystemTTSService.speak` only clears its record (`AutomaticTTSService.kt:139–143`); it does not call `engine.stop()`.

**Reader effect.** Start device speech, then install the optional pack from Display & Themes while listening. The existing suspended call still belongs to the device, but Pause/Resume now address Kokoro, and the download observer can hide the active player by publishing STOPPED. Starting again cancels the old coroutine without stopping its device utterance, then starts Kokoro. Both engines can be audible together until the device utterance ends. The file-presence check can switch ownership during extraction, even before WorkManager announces success.

**Fix.** Keep one engine as the owner of an active reading; change it only after stopping and completing the old reading. Download completion must not overwrite an active session's transport state.

**Confidence: high.** The brief explicitly says the Kokoro path was not run; the three added tests exercise only `SystemTTSService`.

### F4 — P2: an installed but unreadable pack disables the working device fallback and offers no repair

**Evidence.** `reader/speech/AutomaticTTSService.kt:36` selects Kokoro solely by file presence, quoted in F3. `reader/speech/KokoroTTSController.kt:97–99` handles initialization failure as:

```kotlin
} catch (e: Exception) {
    Log.e("KokoroTTS", "Failed to initialize engine", e)
    _status.value = SpeechStatus.UNAVAILABLE
```

`reader/speech/ReaderSpeechController.kt:92–93` now preserves that UNAVAILABLE state when the pack exists:

```kotlin
_status.value = if (ttsStatus == SpeechStatus.UNAVAILABLE &&
    !TTSDownloadWorker.isModelDownloaded(appContext)) SpeechStatus.MODEL_NOT_DOWNLOADED else ttsStatus
```

The only reader download row is guarded by `reader/ReaderScreen.kt:1126`:

```kotlin
if (!voicePackInstalled) {
```

And `reader/speech/TTSDownloadWorker.kt:67–68` refuses to replace a pack passing its existence check:

```kotlin
if (isModelDownloaded(applicationContext)) {
    return@withContext Result.success()
```

**Reader effect.** Nonempty but invalid model files, or another persistent initialization failure, leave Automatic choosing an unusable engine even if a device voice works. Read Aloud silently retries/skips through text; the reader has neither a fallback choice nor a repair download. Settings reports that the pack could not be opened but provides no recovery. The presence predicate checks nonempty files and an existing data directory, not whether the model opens.

**Fix.** Fall back to the device when Kokoro cannot initialize, and expose a repair path that can actually replace the installed pack.

**Confidence: high** for a persistent caught initialization failure; corrupt native models may also have failure modes outside that catch, which were not exercised.

**Privacy checks that looked right, with a limit.** Initial status is UNAVAILABLE; a successful `setVoice` of a filtered offline voice is required before STOPPED. An unsafe default or failed setter therefore does not directly unlock `speak`. `SystemTTSService.setVoice` is a no-op (`AutomaticTTSService.kt:171`), and Automatic's setter only addresses offline Kokoro (`:54`). The installed Android SDK source stores the selected voice name in this TTS client's parameters, so merely changing the global default is not evidence that this client starts using it. I found **no demonstrated network-voice leak through these paths**. However, the offline check runs only at initialization, not before each utterance: an engine changing the advertised properties/meaning of its selected voice later is not checked. `SystemTTSServiceTest.kt:39–42` only calls `onDeviceVoice(...)`; its name, `aVoiceThatNeedsTheNetworkIsNeverChosen`, does not prove the lifetime privacy guarantee. No engine-reconfiguration experiment was run, so I am not presenting a proven text leak.

## 2. 3eb — links tapped in a work

### F5 — P2: matching against the entire URL lets query/fragment text change the destination

**Evidence.** `reader/ReaderLinkHandler.kt:35–37` tries a work before a tag:

```kotlin
authorFromUrl(url)?.let { return ReaderLinkDestination.Author(it) }
WorkTags.ao3WorkIdFromUrl(url)?.let { return ReaderLinkDestination.WorkDetail(it) }
tagFromUrl(url)?.let { return ReaderLinkDestination.TagSearch(it) }
```

`works/WorkTags.kt:7–11` searches the whole string:

```kotlin
val marker = "/works/"
val index = url.indexOf(marker)
// ...
return url.substring(index + marker.length).takeWhile(Char::isDigit)
```

`reader/ReaderLinkHandler.kt:51` strips a query but not a fragment from a tag:

```kotlin
val raw = url.substring(index + marker.length).substringBefore('/').substringBefore('?')
```

**Reader effect.** `https://archiveofourown.org/tags/Fluff?next=/works/123` opens work 123 rather than Fluff. `https://archiveofourown.org/tags/Fluff#top` searches for the literal tag `Fluff#top`. The host check is correct in both cases; parsing the remainder is not. No server behavior or network access is needed to establish these classifier outputs.

**Fix.** Classify decoded path segments from one parsed URL, keeping query and fragment out of identity extraction.

**Confidence: high.** The tests cover an external host whose query mentions AO3, but not an AO3 URL whose query/fragment contains another route.

**Looked right.** `URI.host` plus the exact/dot-bounded AO3 suffix rejects a look-alike host, `archiveofourown.org.evil.example`, and `archiveofourown.org@evil.example`. Subdomains of AO3 are intentionally accepted. HTTP AO3 links are routed to canonical native destinations rather than fetched at their original HTTP address. The classifier does lack a scheme restriction before its AO3 branch (even `ftp://archiveofourown.org/users/a` classifies as an author), but that does not make an outsider's host AO3 or launch that scheme. `Routes.authorProfile` and `Routes.tagWorks` encode the argument using `URLEncoder` with `%20` spaces (`app/Routes.kt:87,213,221`); `routeArg` does not decode it a second time (`:223–224`). A tag's `/` or `%` cannot inject navigation segments. AO3's munged tag characters and literal `+` are handled deliberately.

## 3. 3dy / 3dz — keeping typed words

### F6 — P1: a queue's final autosave is cancelled when the page leaves

**Evidence.** `library/QueueSettingsScreen.kt:84,188–190`:

```kotlin
val scope = rememberCoroutineScope()
// ...
onValueChange = {
    notes = it
    scope.launch { notesWrites.withLock { writeQueue(repository, current, tags, notes = notes) } }
}
```

**Reader effect.** If the last write is waiting for the mutex or Room when the reader leaves the page, the composition-owned scope is cancelled. Its pending final text need not reach the database. The mutex orders surviving jobs; it does not make them survive navigation. This is the same type-and-leave loss 3dy says it fixed, narrowed to a delayed database/write backlog.

`android/app/src/test/java/io/github/cidy02/kudos/library/QueueDescriptionTest.kt:49–50` explicitly waits for persistence while the screen stays mounted:

```kotlin
compose.onNodeWithContentDescription("Description").performTextInput("Night bus reads")
compose.waitUntil(5_000) { runBlocking { repository.getQueue(queue.id)?.notes } == "Night bus reads" }
```

That proves a save while editing, not a save on immediate departure.

**Fix.** Give queued edits a persistence lifetime that survives leaving the composition, and verify typing followed by immediate navigation with a deliberately suspended first write.

**Confidence: high** for the cancellation window; no forced-delay device reproduction was run.

### F7 — P1: changing another queue setting can erase an already saved description

**Evidence.** The autosave above does not refresh the screen's `queue`. `library/QueueSettingsScreen.kt:253` changes colour using:

```kotlin
writeQueue(repository, current, tags, hue = swatch.hue, colorHex = null)
```

The helper's defaults at `:326–329` come from that older screen snapshot:

```kotlin
notes: String? = queue.notes,
hue: Double? = queue.hue,
colorHex: String? = queue.colorHex,
keep: Boolean = queue.keepsWorksOffline != false
```

At `:331–339`, it passes all fields to `updateQueue`, including `notes = notes` and `tagNames = tags`. `library/ReadingQueueRepository.kt:344–345` treats the old description as a new edit:

```kotlin
if ((edit.notes ?: "") != (queue.notes ?: "")) {
    notes = edit.notes
```

**Reader effect.** Open a queue with no description, type one, and wait until it is saved. Pick a colour before reopening the page. That colour write still defaults to `current.notes == null`, and replaces the saved description with null. Removing a tag or changing Keep offline can do the same. This needs no unlucky write ordering. Concurrent description jobs can also restore stale colour, tags, or Keep values, because only description jobs take `notesWrites` and every job submits the whole edit.

**Fix.** Persist only the changed field against fresh data, or serialize all edits around one current edit state. Add a test that types, changes colour/Keep/tags, leaves, and reopens.

**Confidence: high.** The new test never changes another setting after typing.

### F8 — P1: keeping a note during reader disposal queues it in the ViewModel being destroyed

**Evidence.** `reader/ReaderNoteEditor.kt:74–75` performs the save on disposal:

```kotlin
DisposableEffect(annotation.id) {
    onDispose { if (!finished[0] && draft.trim() != saved) onKeep(draft.trim()) }
}
```

`reader/ReaderScreen.kt:817` wires this to:

```kotlin
onKeep = { note -> viewModel.updateNote(annotation.id, note) },
```

`reader/ReaderViewModel.kt:317–319` starts another cancellable job:

```kotlin
fun updateNote(id: String, note: String) {
    viewModelScope.launch {
        annotationEditMutex.withLock { annotationRepository.updateNote(id, note) }
```

The ViewModel belongs to the reader navigation entry (`app/AppNavHost.kt:1080–1093`), whose Back action pops that entry.

**Reader effect.** Dismissing just the note sheet keeps the reader ViewModel alive and works. Disposing the whole reader can clear that ViewModel while the keep job is waiting for an earlier recolour or database operation. The final note is then cancelled before it is saved. The new comment explicitly promises to cover “the reader closing”, but its save lifetime does not cover that case.

**Fix.** Complete/persist the pending note before destroying its owner, or enqueue the write in a persistence scope independent of that navigation entry. Test actual reader removal with a blocked annotation edit, not only the editor callback.

**Confidence: high** about the cancellation risk; whether a particular close loses the note depends on operation/teardown timing. `ReaderNoteEditorKeepTest` only appends the callback's text to a list; it does not exercise the ViewModel or Room.

**Other note checks looked right.** The effect is keyed by annotation ID and its callback captures that annotation's ID. Cancel, Done, and Delete set `finished` before removing the editor, so ordinary Done does not also run `onKeep`. Note/recolour/delete operations from this ViewModel share `annotationEditMutex`; `AnnotationRepository.updateNote` returns when the ID no longer exists (`reader/AnnotationRepository.kt:62`). I found no ordinary editor path that saves onto a different highlight or resurrects its own confirmed deletion. Ordinary rotation is handled without Activity recreation (`android/app/src/main/AndroidManifest.xml:22`), so it does not normally trigger this disposal. Actual composition disposal can save a partial draft; keeping that draft is the requested behavior, and normal rotation is not evidence of a premature-save bug.

## 4. 3dj — author page, HTML, pseud decoding

**Looked right for the requested HTML boundary.** `ui/components/AO3RichText.kt:49,55` uses:

```kotlin
private val safelist: Safelist = Safelist.basic().removeProtocols("a", "href", "ftp", "mailto")
fun clean(html: String): String = Jsoup.clean(html, AO3Constants.BASE_URL, safelist)
```

This retains text formatting and HTTP(S) anchors, not images, scripts, event handlers, `javascript:`, `intent:`, or `mailto:` links. Rendering is `AnnotatedString.fromHtml`, not a WebView. External opening occurs in the link interaction listener (`:36–40`), after a reader taps; merely displaying the bio does not invoke `openUri`. The sanitizer test includes script and tracking-image input as well as unsafe schemes. No bypass was found by inspection; no fuzzing was run.

**Pseud decoding looked right.** `network/ao3/author/AO3AuthorParser.kt:384–388` gets decoded `HttpUrl.pathSegments`; `AO3AuthorUrls.kt:32,64` later uses `addPathSegment(pseud.trim())`. `%20` becomes a space and is encoded once on output; `%2520` becomes the literal `%20` name and is correctly encoded back as `%2520`. Encoded slashes remain one segment until the decoded value is given to `addPathSegment`. I found no double-decode/double-encode fault in the changed path.

The byline collision below belongs to both 3dj's lookup and 3do's caller.

## 5. 3do — which author account opens

### F9 — P2, conditional: two identical stored display labels always open the first account

**Evidence.** `network/ao3/author/AO3AuthorIdentities.kt:46–49`:

```kotlin
val identity = identities.filterIsInstance<JsonObject>().firstOrNull {
    it.text("displayName") == displayName.trim() && it.text("kind") in setOf("registered", "orphaned")
} ?: return null
val username = identity.text("username") ?: return null
```

`works/WorkDetailScreen.kt:1494–1495` passes only the displayed name:

```kotlin
isLinked = state::hasAccount,
onOpenAuthor = { name -> onOpenAuthor(state.accountByline(name)) }
```

**Reader effect.** If two stored author links both have display label `Alex`, for accounts `FirstAccount` and `SecondAccount`, every `Alex` resolves to `FirstAccount`. The lookup cannot distinguish the second link. The recording function permits both entries and does not enforce unique display labels. The summary parser can even deduplicate identical labels (`network/ao3/search/AO3SearchParser.kt:243–246`).

**Fix.** Carry each recorded identity alongside its displayed author, or fail closed for an ambiguous label instead of choosing the first.

**Confidence: high** for the result given duplicate literal labels; **medium for occurrence in live AO3 markup**. Ordinary nondefault pseud labels that include `(account)` distinguish otherwise equal pseud names. No real duplicate-label page was fetched, and I am not claiming that every pair of equal pseuds triggers this. The existing test supplies distinct display labels only.

**Looked right otherwise.** A plain imported name with no identity is no longer linked. A pseud equal to another account's username does not by itself select that other account: matching is against the recorded display label, and navigation uses the recorded username. The final `fromByline` interpretation is backed by the recorded route, not a lookup of the bare pseud.

## 6. 3dq — Browse state and compact counts

### F10 — P2: a rounded lower-bound label can contradict the works it admits

**Evidence.** `ui/subject/SubjectComponents.kt:115–119` deliberately promotes a rounded value across a unit boundary:

```kotlin
if (rounded >= java.math.BigDecimal(1_000) && index < compactUnits.lastIndex) {
    rounded = compactRound(magnitude, compactUnits[++index].first)
}
rounded.stripTrailingZeros().toPlainString() + compactUnits[index].second
```

The live Home-section filter summary uses that count as an exact-looking minimum, `home/HomeSectionListScreen.kt:901`:

```kotlin
lower.isNotEmpty() -> add(lower.toIntOrNull()?.let { "${it.compactCount()}+ words" } ?: "Words ≥ $lower")
```

**Reader effect.** Set the minimum to 999,950 words. The summary says `1M+ words`, yet works between 999,950 and 999,999 qualify. Less extreme bounds also lose precision. These are filter instructions, not merely approximate popularity figures, and their wording can make valid results look wrongly filtered. The helper test explicitly expects `999_950 to "1M"`; it does not test callers that turn the rounded figure into a threshold.

**Fix.** Show the exact entered bound in filter labels. Keep compact notation for approximate count displays.

**Confidence: high.** The Home helper is called at `HomeSectionListScreen.kt:726`. Most other callers are statistic/header/chip displays where rounding is expected; I did not find arithmetic or pagination using the formatted string.

**Browse's state fix looked right.** `currentLibrary` is a delegated `rememberUpdatedState` read inside `snapshotFlow` (`browse/BrowseScreen.kt:77,88–94`). This observes library changes instead of freezing the initial empty list. Computation is dispatched to `Dispatchers.Default`, and collecting rather than cancelling each pass lets a result land.

## 7. 3dl — Contents and position calculation

### F11 — P2: the new position aggregation runs on the reader's main thread at every opening

**Evidence.** `reader/ReaderScreen.kt:354–355`:

```kotlin
val chapterStarts by androidx.compose.runtime.produceState(emptyMap<String, Int>(), publication) {
    value = ReadiumTocAdapter.startPercents(publication)
}
```

`reader/readium/ReadiumTocAdapter.kt:58–65` reads and copies the complete position list, then groups every position:

```kotlin
suspend fun startPercents(publication: Publication): Map<String, Int> = startPercents(
    runCatching { publication.positions() }.getOrDefault(emptyList())
        .map { it.href.toString() to it.locations.totalProgression }
)
// ...
positions.groupBy({ ReaderSectionBuilder.hrefKey(it.first) }, { it.second })
```

**Reader effect.** The producer is launched in the composition's main-thread context, and neither this adapter nor its aggregation changes dispatcher. `suspend` does not dispatch CPU work away from Main. The cached Readium 3.3.0 bytecode confirms `positions()` delegates to the position service and that EPUB position generation has synchronous locator-building loops; the app's map/grouping also always runs in the caller context. A work with a large position list can therefore stall reader input/rendering while building percentages, even if Contents is never opened. A second main-thread effect separately requests `positionsByReadingOrder()` at `ReaderScreen.kt:412–414`; the new feature need not request its own full list.

**Fix.** Reuse the existing position result and compute first-per-file percentages off Main. It only needs the first position per file, not a list of all progressions grouped under every file.

**Confidence: high** about threading and full-list allocation; **medium** about noticeable latency at a particular work size. No timing measurement was allowed or made. The two new tests use two rows/a handful of synthetic positions, not a large publication or dispatcher assertion.

**Looked right on ordinary failure/UI behavior.** Contents is not gated on the percentages becoming ready. Exceptions from the added `positions()` request become an empty map, so percentages are omitted rather than blocking the sheet on an error state. The added title, Done, and tab wiring looked right. The older separate position effect is not protected by that catch; this review does not claim that the new catch makes all reader position failures safe.

## 8. 3ds / 3ec — removed screens

### F12 — P1: replacing Tag Works also adds a hidden fandom filter to every tag

**Evidence.** `app/AppNavHost.kt:461–467` now routes a general tag into:

```kotlin
FandomWorksScreen(
    fandomName = tagName,
    isTag = true,
```

`browse/FandomWorksScreen.kt:131` still calls:

```kotlin
repository.worksForFandom(fandomName, page, filters)
```

`network/ao3/browse/AO3BrowseRepository.kt:95–96` unconditionally adds the name as a fandom:

```kotlin
val searchFilters = (filters ?: browseBaseline()).copy(fandom = trimmed)
return searchRepository.searchTagWorks(trimmed, searchFilters, page)
```

`network/ao3/search/AO3SearchUrlBuilder.kt:79` sends it:

```kotlin
add("work_search[fandom_names]", filters.fandom)
```

**Reader effect.** Tap an ordinary additional/relationship/character tag, such as `Fluff`. The route requests `/tags/Fluff/works` **and** `work_search[fandom_names]=Fluff`. The extra constraint asks for a fandom named Fluff, so a tag with works can return none, an error, or a wrongly narrowed result. `isTag` changes empty-state words only; it never changes this query construction. Reset cannot remove the constraint, and the page hides the fandom picker. The outgoing query is certain; the precise server response was not checked because AO3 contact was prohibited.

**Why the replacement test misses it.** `android/app/src/test/java/io/github/cidy02/kudos/account/Brief3caScreenTest.kt:158` sets `client.emptyWorks = true`; its fake client at `:438` answers every work index with:

```kotlin
emptyWorks && isIndex -> "<ol class='work index group'></ol>"
```

The test checks request counts, completion filtering/reset, and the tag/fandom empty-state wording. It never asserts absence of `work_search[fandom_names]` for a general tag. It therefore stays green for this regression.

**Fix.** Share the screen while preserving general-tag query semantics: put the tag in the path, and only add a fandom filter the reader actually selected. Add a request-shape assertion using a non-fandom tag.

**Confidence: high.** This is an observable difference in constructed requests, without depending on an untested UI race.

**The deletion checks themselves looked right.** No surviving Kotlin, navigation, manifest, shrinker, or reflection reference to `TagWorksScreen` or the deleted account-list functions was found. The `account-list` destination calls `AccountWorksListScreen`; the `tag-works` destination survives and calls `FandomWorksScreen`. `AccountScreen` itself remains live; it is the old helpers inside it that were removed. The located reflective screen reference is for the writing editor, unrelated to these deletions. The problem is the replacement's request above, not a dangling class name. The brief's chrome-button lead was not reproduced; the registration code preserves arrival order, so I found no concrete production failure to report for that lead.

## 9. 3dw — Settings header

**Looked right for the requested missing-header question.** All 16 destinations in `settings/SettingsScreen.kt:54–105` draw a header: the hub uses `SubjectHeaderBlock`, and the other pages use `SettingsPage`, including Privacy's data screen and the backup/queue wrappers. `settings/SettingsChrome.kt:95–101` draws the inset and header; `hasSubjectHeader = true` does not itself remove the shell's floating Back control. I found no destination made headerless by this change. This is code verification, not a new visual sign-off.

## 10. Remaining items — 3ea / 3dr / 3dt / 3dv

### F13 — P2: the fandom/tag header's sort menu keeps the previous sort's direction

**Evidence.** `browse/FandomWorksScreen.kt:281`:

```kotlin
onSortSelected = { sort -> filters = filters.copy(sort = sort); load() },
```

The existing sort model says otherwise, `network/ao3/search/AO3SearchFilters.kt:437–438`:

```kotlin
val naturalDirection: AO3SortDirection
    get() = if (this == CREATOR || this == TITLE) AO3SortDirection.ASCENDING else AO3SortDirection.DESCENDING
```

The filter sheet applies that rule (`search/SearchFilterSheet.kt:146`):

```kotlin
onFiltersChange(filters.copy(sort = it, sortDirection = it.naturalDirection))
```

**Reader effect.** From the default Date Updated descending list, choose Title in the new header menu. It requests descending titles, unlike choosing Title in Filters. Conversely, a direction selected earlier can make a later popularity/date sort run backwards. The compact menu does not expose that retained direction, so the same named choice produces different ordering depending on earlier actions.

**Fix.** Apply `sort.naturalDirection` when the header changes the sort, matching the filter sheet. The Search header uses the same pattern and is another caller to check when fixing it.

**Confidence: high.** The submitted direction is explicitly used by the URL builder (`AO3SearchUrlBuilder.kt:111–112`).

**3ea looked right within its stated limit.** The filter uses whole normalized-line equality for labels and the closing plug, so a longer note beginning with a label survives. The installed Readium `Content.text` implementation uses a newline separator, supporting the paragraph split. URL replacement and punctuation handling match the stated intent and the iOS filter's approach. The 80,000-character listening limit is documented in both code and brief; it is not a newly discovered fault. That cap is applied after `content.text()` materializes the text, so it should not be read as a memory bound, but this was already the extraction path before 3ea.

**3dr looked right.** Settings collects imported fonts and calls `ReaderFontCatalog.name` with the current reader font ID. Unknown/deleted IDs fall back to System. The hero's own-profile flag compares the signed-in username to `route.username`, case-insensitively (`author/AuthorProfileScreen.kt:685`), not to the displayed pseud. No fault found in these changes.

**3dt looked right.** `author/AuthorProfileComponents.kt:451–466` draws a fallback under the asynchronously loaded image; an absent/failed image leaves the fallback visible, and the surrounding box retains the supplied accessibility label. The shared avatar does not initiate a new non-image action. No functional regression found in the consolidation.

## Fix first

- **F12:** remove the hidden fandom constraint from general tag links; the current test accepts the wrong request.
- **F7 / F6:** keep queue descriptions through other setting changes and through immediate departure.
- **F8:** persist the final note outside the lifetime of the reader being destroyed.
- **F2 / F3:** make speech submission and engine handoff obey Stop/Pause and have one active owner.
- **F4 / F1:** recover from an unreadable pack and make installed offline engines discoverable.
- **F5 / F13:** parse only URL paths for routing and give header sort choices their expected direction.
- **F10 / F11 / F9:** keep filter bounds exact, move position aggregation off Main, and refuse ambiguous author labels.
