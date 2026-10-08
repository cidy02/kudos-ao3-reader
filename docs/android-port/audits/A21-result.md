# Audit A21: what the two apps write to their logs

This document audits every log statement across the iOS and Android Kudos reader applications that writes non-constant values into system logs (`OSLog` on iOS and `android.util.Log` on Android).

Kudos is a reader for Archive of Our Own (AO3). What a user reads, searches for, bookmarks, writes, and downloads is private, and so is their account username and local library contents.

## Log Statements with Non-Constant Values

| app | `path:line` | the statement, quoted | each interpolated value and what it holds | its privacy marker (iOS: `.public`, `.private`, none; Android: none exists) | class |
|---|---|---|---|---|---|
| iOS | `kudos-ao3-reader/Features/Reader/ReaderView.swift:504` | `Log.epub.info("Opened EPUB: \(parsed.chapters.count) chapters")` | `parsed.chapters.count`: `Int` count of parsed chapters in EPUB spine (`EPUBParsedDocument.chapters`) | none (private by default) | **C** |
| iOS | `kudos-ao3-reader/Features/Reader/ReaderView.swift:509` | `Log.epub.error("Couldn't open EPUB: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` error description thrown by `EPUBParser.parse`; can contain filesystem path of EPUB directory | .public | **E** |
| iOS | `kudos-ao3-reader/Features/Home/HomeView.swift:593` | `Log.network.notice( "Subscriptions refresh failed: \(UserFacingError.message(for: error), privacy: .public)" )` | `UserFacingError.message(for: error)`: `String` mapped user-facing error message for failed subscriptions fetch | .public | **E** |
| iOS | `kudos-ao3-reader/Features/Search/FandomListView.swift:436` | `Log.network.notice("Fandom list refresh failed: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` network/transport error description from AO3Client mediaCategories fetch | .public | **E** |
| iOS | `kudos-ao3-reader/Features/Search/FandomListView.swift:445` | `Log.network.notice("Fandom list refresh failed: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` network/transport error description from fandom list refresh | .public | **E** |
| iOS | `kudos-ao3-reader/Features/Search/MediaBrowserView.swift:872` | `Log.network.notice("Browse refresh failed: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` network/transport error description from media browse refresh | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroPackInstaller.swift:50` | `Log.tts.error( "Kokoro ANE install failed: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` error description from CoreML model download/compilation; can contain model cache URLs or file paths | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroPackInstaller.swift:77` | `Log.tts.info("Kokoro compute units: \(routing, privacy: .public)")` | `routing`: `String` hardware execution provider label (`'default (ANE per stage)'` or `'cpuOnly (crash recorded)'`) | .public | **C** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroTTSService.swift:138` | `Log.tts.error( "Kokoro ANE synthesize failed: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` error description from CoreML model audio synthesis failure | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroTTSService.swift:165` | `Log.tts.info( "Kokoro ANE \(clip.timingsMs, privacy: .public)ms phonemes=\(clip.phonemeCount, privacy: .public)" )` | `clip.timingsMs`: `Int` synthesis duration in milliseconds; `clip.phonemeCount`: `Int` count of phonemes generated | .public | **C** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroTTSService.swift:324` | `Log.tts.error("Kokoro ANE resume failed: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` audio playback resume failure description from AVAudioEngine/AVAudioSession | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroTTSService.swift:420` | `Log.tts.error("AVAudioEngine.start failed: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` CoreAudio/AVAudioEngine start failure description | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/KokoroCastPreflight.swift:104` | `Log.tts.error( "Pre-flight could not ready the Kokoro manager: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` initialization failure description from CoreML Kokoro manager readying | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechController.swift:477` | `Log.tts.error("speak() failed: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` speech playback failure description from TTS service | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechController.swift:522` | `Log.tts.error( "Audition failed: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` voice audition playback failure description | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:565` | `Log.epub.info("Opened EPUB (Readium): \(self.toc.count) TOC entries")` | `self.toc.count`: `Int` count of Table of Contents items in `[ReadiumTOCEntry]` | none (private by default) | **C** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:570` | `Log.epub.error("Couldn't open EPUB (Readium): \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` Readium EPUB open error; can contain EPUB file path | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/SherpaKokoroTTSService.swift:145` | `Log.tts.error("AVAudioEngine.start failed: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` AVAudioEngine start error description | .public | **E** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/SherpaKokoroTTSService.swift:227` | `Log.tts.debug("\(primingMessage, privacy: .public)")` | `primingMessage`: `String` containing PCM buffer count (`Int`) and audio seconds duration (`Double`) | .public | **C** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/SherpaKokoroTTSService.swift:366` | `Log.tts.info("\(loadMessage, privacy: .public)")` | `loadMessage`: `String` containing model pack and execution provider enum case names | .public | **C** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/SherpaKokoroTTSService.swift:581` | `Log.tts.debug("\(diagnosticMessage, privacy: .public)")` | `diagnosticMessage`: `String` containing queued audio duration and player elapsed seconds (`Double`) | .public | **C** |
| iOS | `kudos-ao3-reader/Features/ReaderReadium/SherpaKokoroTTSService.swift:770` | `Log.tts.debug("\(diagnosticMessage, privacy: .public)")` | `diagnosticMessage`: `String` containing generated frame count, synthesis seconds, audio seconds, and waveform metrics (`Double`/`Float`) | .public | **C** |
| iOS | `kudos-ao3-reader/Utilities/ModelContext+SaveBestEffort.swift:42` | `Log.library.error( "\(String(describing: reason), privacy: .public): \(error.localizedDescription, privacy: .public)" )` | `String(describing: reason)`: `StaticString` operation context description (e.g. 'Saving the re-converted work failed'); `error.localizedDescription`: `String` SwiftData save error description (can contain store path or model attributes) | .public | **E** |
| iOS | `kudos-ao3-reader/Services/AO3AuthService.swift:511` | `Log.auth.error("Could not restore the AO3 session: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` Keychain session restoration error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/AO3AuthService.swift:622` | `Log.auth.error("Could not delete the saved AO3 session: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` Keychain session deletion error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/AO3AuthService.swift:673` | `Log.auth.error( "Could not refresh the saved AO3 session: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` Keychain session refresh write error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/AO3AuthService.swift:888` | `Log.auth.error("Could not save the AO3 session: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` Keychain session save error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/AO3AuthService.swift:967` | `Log.auth.error( "Could not refresh the saved AO3 session: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` Keychain session refresh write error description during WebKit cookie restoration | .public | **E** |
| iOS | `kudos-ao3-reader/Services/AO3AuthService.swift:1023` | `Log.auth.error( "Could not delete the expired AO3 session: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` Keychain expired session deletion error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/AO3AuthService.swift:1059` | `Log.auth.error( "AO3 session removal is still pending: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` Keychain session removal retry error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/AO3Client.swift:218` | `Log.network.notice("Pacer backlog: waiting \(step.wait, privacy: .public)s")` | `step.wait`: `Double` pacer wait duration in seconds | .public | **C** |
| iOS | `kudos-ao3-reader/Services/AO3Client.swift:293` | `Log.network.debug("GET \(url.absoluteString, privacy: .public)")` | `url.absoluteString`: `String` full unauthenticated AO3 request URL (carries search queries/filters `/works?work_search[...]`, specific work URLs `/works/:id`, tag URLs, user profile URLs) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/AO3Client.swift:365` | `Log.network.warning( "Request failed (\(error.localizedDescription, privacy: .public)); retry \(attempt) in \(delay)s" )` | `error.localizedDescription`: `String` network error description (URLError repeats request URL); `attempt`: `Int` retry attempt count; `delay`: `Double` retry wait duration in seconds | .public (`error.localizedDescription`), none (`attempt`, `delay`) | **E, C** |
| iOS | `kudos-ao3-reader/Services/AO3Client.swift:787` | `Log.network.debug("GET (auth) \(request.url?.absoluteString ?? "?", privacy: .public)")` | `request.url?.absoluteString ?? "?"`: `String` full authenticated GET request URL (carries user private endpoints `/users/:username/readings` [history], `/users/:username/bookmarks`, subscriptions, inbox, and query tokens) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/AO3Client.swift:904` | `Log.network.debug("POST (auth) \(request.url?.absoluteString ?? "?", privacy: .public)")` | `request.url?.absoluteString ?? "?"`: `String` full authenticated POST request URL (carries write endpoints for comments, kudos, work posting, collection items) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/AO3Client.swift:1324` | `Log.network.info("Downloading EPUB for work \(workID)")` | `workID`: `Int` AO3 work ID being downloaded | none (private by default) | **P** |
| iOS | `kudos-ao3-reader/Services/AO3Client.swift:1840` | `Log.network.error( "Parsed 0 of \(blurbs.count, privacy: .public) '\(blurbSelector, privacy: .public)' blurbs — markup changed?" )` | `blurbs.count`: `Int` count of blurb elements parsed; `blurbSelector`: `String` CSS selector constant (`'li.work.blurb.group'` / `'li.bookmark.blurb.group'`) | .public | **C** |
| iOS | `kudos-ao3-reader/Services/AO3SparseWorkEnricher.swift:57` | `Log.network.notice( "Sparse work \(work.id, privacy: .public) could not be enriched: \(error.localizedDescription, privacy: .public)" )` | `work.id`: `Int` AO3 work ID (`AO3WorkSummary.id`); `error.localizedDescription`: `String` metadata fetch error description (can repeat work URL) | .public (both) | **P, E** |
| iOS | `kudos-ao3-reader/Services/DownloadQueue.swift:182` | `Log.library.error( "Queue download failed for work \(item.id): \(error.localizedDescription, privacy: .public)" )` | `item.id`: `Int` AO3 work ID; `error.localizedDescription`: `String` download/import error description (can contain download URL or file path) | none (`item.id`), .public (`error.localizedDescription`) | **P, E** |
| iOS | `kudos-ao3-reader/Services/DownloadQueue.swift:187` | `Log.library.info("Download queue finished: \(self.finishedCount) processed, \(self.failedCount) failed")` | `self.finishedCount`: `Int` count of finished downloads; `self.failedCount`: `Int` count of failed downloads | none (private by default) | **C** |
| iOS | `kudos-ao3-reader/Services/ExternalFileImport.swift:61` | `Log.library.error("Opening \(fileName, privacy: .private) failed: \(reason, privacy: .private)")` | `fileName`: `String` imported file name; `reason`: `String` import failure reason | .private (both) | **P, E** |
| iOS | `kudos-ao3-reader/Services/ExternalFileImport.swift:93` | `Log.library.error("Opening \(fileName, privacy: .private) failed: \(reason, privacy: .private)")` | `fileName`: `String` imported file name; `reason`: `String` import failure reason | .private (both) | **P, E** |
| iOS | `kudos-ao3-reader/Services/FolderSyncBackgroundTask.swift:53` | `Log.library.notice( "Could not schedule folder-sync background refresh: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` background task scheduler error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/FolderSyncService.swift:533` | `Log.library.notice( "Legacy sync package fold failed: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` filesystem error description during sync package fold migration; can contain sync folder path | .public | **E** |
| iOS | `kudos-ao3-reader/Services/FolderSyncService.swift:627` | `Log.library.error("Library folder sync failed: \(message, privacy: .public)")` | `message`: `String` (`error.localizedDescription`) folder sync filesystem error description; can contain sync folder path or file names | .public | **E** |
| iOS | `kudos-ao3-reader/Services/ImportedDocumentConverter.swift:110` | `Log.library.info("Import sniffed \(format.rawValue, privacy: .public) for \(url.lastPathComponent, privacy: .public)")` | `format.rawValue`: `String` detected file format (`'epub'`, `'html'`, etc.); `url.lastPathComponent`: `String` file name of user document being imported | .public (both) | **C, P** |
| iOS | `kudos-ao3-reader/Services/KudosBackup.swift:139` | `Log.library.error( """ Backup entry \(name, privacy: .public) failed its CRC-32 check; \ treating it as missing rather than restoring damaged bytes. """ )` | `name`: `String` backup entry path inside ZIP (`'Originals/<fileName>'`, `'Works/<title>.epub'`, `'Fonts/<name>'`) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/KudosBackup.swift:2514` | `Log.library.notice( "Skipped an invalid backup EPUB: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` EPUB import error description; can contain temporary EPUB file path | .public | **E** |
| iOS | `kudos-ao3-reader/Services/KudosBackup.swift:2575` | `Log.library.notice( "Preserving ambiguous collection \(archived.id.uuidString, privacy: .public)" )` | `archived.id.uuidString`: `String` UUID of user collection (`WorkCollection.id`) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/KudosBackup.swift:2808` | `Log.library.notice( "Reviving queue \(archivedQueueID, privacy: .public) because backup is newer than tombstone" )` | `archivedQueueID`: `String` UUID of user reading queue (`ReadingQueue.id.uuidString`) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/KudosBackup.swift:2813` | `Log.library.notice( "Preserving queue \(archivedQueueID, privacy: .public) because tombstone conflict is ambiguous" )` | `archivedQueueID`: `String` UUID of user reading queue (`ReadingQueue.id.uuidString`) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/KudosBackup.swift:2834` | `Log.library.notice( "Preserving existing queue \(archived.id.uuidString, privacy: .public) despite tombstone conflict" )` | `archived.id.uuidString`: `String` UUID of user reading queue (`ReadingQueue.id.uuidString`) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/KudosBackupExport.swift:133` | `Log.library.error("Backup skips unreadable font \(name, privacy: .public).")` | `name`: `String` file name of custom user font (`font.fileName`) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/KudosBackupExport.swift:137` | `Log.library.error("Backup skips font \(name, privacy: .public): \(reason, privacy: .public)")` | `name`: `String` file name of custom user font; `reason`: `String` font rejection reason description | .public (both) | **P, E** |
| iOS | `kudos-ao3-reader/Services/KudosBackupExport.swift:143` | `Log.library.error("Backup skips font \(name, privacy: .public): total reached.")` | `name`: `String` file name of custom user font (`font.fileName`) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/PDFWorkConverter.swift:144` | `Log.library.info("PDF has no usable text layer (\(totalCharacters) chars); trying OCR")` | `totalCharacters`: `Int` count of extracted text characters from PDF pages | none (private by default) | **C** |
| iOS | `kudos-ao3-reader/Services/PDFWorkConverter.swift:172` | `Log.library.notice( "\(emptyPages.count) pages had no text layer; OCR ran on the first \(maxOCRPages)" )` | `emptyPages.count`: `Int` count of empty pages; `maxOCRPages`: `Int` maximum OCR page count budget (30) | none (private by default) | **C** |
| iOS | `kudos-ao3-reader/Services/PDFWorkConverter.swift:180` | `Log.library.info("Recovered page \(index + 1) of the PDF by OCR")` | `index + 1`: `Int` 1-based page number recovered by OCR | none (private by default) | **C** |
| iOS | `kudos-ao3-reader/Services/PDFWorkConverter.swift:246` | `Log.library.notice( "OCR capped at \(maxOCRPages) of \(document.pageCount) pages; the rest were dropped" )` | `maxOCRPages`: `Int` maximum OCR page budget (30); `document.pageCount`: `Int` total page count of PDF | none (private by default) | **C** |
| iOS | `kudos-ao3-reader/Services/PDFWorkConverter.swift:301` | `Log.library.error("OCR failed for a page: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` Vision framework OCR failure error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/PersistenceSync.swift:207` | `Log.library.error("Persistence migration failed (\(stage, privacy: .public)): \(message, privacy: .public)")` | `stage`: `String` migration stage identifier; `message`: `String` migration error message | .public (both) | **C, E** |
| iOS | `kudos-ao3-reader/Services/PersistenceSync.swift:212` | `Log.library.error("Persistence migration failed while saving: \(message, privacy: .public)")` | `message`: `String` database save error description from `context.save()` | .public | **E** |
| iOS | `kudos-ao3-reader/Services/PersistenceSync.swift:309` | `Log.library.info( "Persistence metadata migration checked at \(now.formatted(.iso8601), privacy: .public)" )` | `now.formatted(.iso8601)`: `String` ISO 8601 timestamp of migration check | .public | **C** |
| iOS | `kudos-ao3-reader/Services/PersistenceSync.swift:371` | `Log.library.notice( "EPUB asset missing for work \(work.id.uuidString, privacy: .public)" )` | `work.id.uuidString`: `String` UUID of local work (`SavedWork.id`) | .public | **P** |
| iOS | `kudos-ao3-reader/Services/PreservedWorkService.swift:204` | `Log.library.info("Recently Deleted sweep permanently removed \(count, privacy: .public) record(s)")` | `count`: `Int` count of expired work records permanently swept | .public | **C** |
| iOS | `kudos-ao3-reader/Services/ReadingQueueService.swift:531` | `Log.library.error( "Queue preserve failed for \(work.id.uuidString, privacy: .public): \(message, privacy: .public)" )` | `work.id.uuidString`: `String` UUID of local work; `message`: `String` error description from queue preservation | .public (both) | **P, E** |
| iOS | `kudos-ao3-reader/Services/ReadingQueueService.swift:586` | `Log.library.error( "Couldn't load series for queue preservation: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` SwiftData series fetch error description | .public | **E** |
| iOS | `kudos-ao3-reader/Services/UserDocumentImport.swift:88` | `Log.library.info( "Imported “\(outcome.work.title)” converted from \(format.rawValue, privacy: .public)" )` | `outcome.work.title`: `String` title of imported work; `format.rawValue`: `String` source format enum raw value (`'html'`, `'plainText'`) | none (`outcome.work.title`), .public (`format.rawValue`) | **P, C** |
| iOS | `kudos-ao3-reader/Services/UserDocumentImport.swift:119` | `Log.library.error( "Couldn't preserve the original import: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` original import file copy error; can contain filesystem paths | .public | **E** |
| iOS | `kudos-ao3-reader/Services/WorkAvailability.swift:61` | `Log.library.info("AO3 no longer has work \(id); marking the local copy as the last one")` | `id`: `Int` AO3 work ID determined gone from AO3 | none (private by default) | **P** |
| iOS | `kudos-ao3-reader/Services/WorkAvailability.swift:68` | `Log.library.notice("Availability check for work \(id) was inconclusive: \(reason, privacy: .public)")` | `id`: `Int` AO3 work ID; `reason`: `String` inconclusive check reason description | none (`id`), .public (`reason`) | **P, E** |
| iOS | `kudos-ao3-reader/Services/WorkAvailability.swift:88` | `Log.library.info("Work \(work.ao3WorkID ?? 0) is back on AO3; clearing the last-copy flag")` | `work.ao3WorkID ?? 0`: `Int` AO3 work ID restored on AO3 | none (private by default) | **P** |
| iOS | `kudos-ao3-reader/Services/WorkAvailabilitySweep.swift:139` | `Log.library.info("Availability sweep: checked \(checked), gone \(gone), remaining \(left)")` | `checked`: `Int` checked works count; `gone`: `Int` gone works count; `left`: `Int` remaining works count | none (private by default) | **C** |
| iOS | `kudos-ao3-reader/Services/WorkConversionRecord.swift:58` | `Log.library.error( "Couldn't record the conversion version: \(error.localizedDescription, privacy: .public)" )` | `error.localizedDescription`: `String` conversion version JSON write error; can contain file path | .public | **E** |
| iOS | `kudos-ao3-reader/Services/WorkImporter.swift:57` | `Log.library.error("Couldn't save imported EPUB: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` EPUB replacement error; can contain EPUB file path | .public | **E** |
| iOS | `kudos-ao3-reader/Services/WorkImporter.swift:64` | `Log.library.info("Import revived “\(existing.title)” from Recently Deleted")` | `existing.title`: `String` title of revived work | none (private by default) | **P** |
| iOS | `kudos-ao3-reader/Services/WorkImporter.swift:66` | `Log.library.info("Import merged into existing “\(existing.title)”")` | `existing.title`: `String` title of merged work | none (private by default) | **P** |
| iOS | `kudos-ao3-reader/Services/WorkImporter.swift:107` | `Log.library.error("Couldn't save imported EPUB: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` EPUB save error; can contain EPUB file path | .public | **E** |
| iOS | `kudos-ao3-reader/Services/WorkImporter.swift:114` | `Log.library.info("Imported work “\(title)”")` | `title`: `String` title of imported work | none (private by default) | **P** |
| iOS | `kudos-ao3-reader/Services/WorkImporter.swift:298` | `Log.library.info("Imported user EPUB “\(work.title)”")` | `work.title`: `String` title of imported user EPUB | none (private by default) | **P** |
| iOS | `kudos-ao3-reader/Services/WorkImporter.swift:596` | `Log.library.error("Couldn't copy imported EPUB: \(error.localizedDescription, privacy: .public)")` | `error.localizedDescription`: `String` EPUB file copy error; can contain source and destination file paths | .public | **E** |
| iOS | `kudos-ao3-reader/Services/WorkMetadataRefresh.swift:63` | `Log.network.notice( "Metadata refresh failed for work \(id, privacy: .public): \(message(for: error), privacy: .public)" )` | `id`: `Int` AO3 work ID being refreshed; `message(for: error)`: `String` mapped error message | .public (both) | **P, E** |
| iOS | `kudos-ao3-reader/Services/WorkReconversion.swift:122` | `Log.library.info( "Rebuilt “\(work.title)” with converter v\(ImportedDocumentConverter.converterVersion)" )` | `work.title`: `String` title of re-converted work; `ImportedDocumentConverter.converterVersion`: `Int` converter version integer (2) | none (private by default) | **P, C** |
| iOS | `kudos-ao3-reader/Services/WorkSearchIndex.swift:141` | `Log.library.info("Search index rebuilt for \(stale.count, privacy: .public) work(s)")` | `stale.count`: `Int` count of stale works re-indexed | .public | **C** |
| iOS | `kudos-ao3-reader/Services/WorkUpdateChecker.swift:28` | `Log.network.info("Checking \(due.count) work(s) for AO3 updates")` | `due.count`: `Int` count of works due for update checking | none (private by default) | **C** |
| Android | `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/reader/speech/KokoroTTSController.kt:98` | `Log.e("KokoroTTS", "Failed to initialize engine", e)` | `e`: `java.lang.Exception` thrown during `OfflineTts` initialization; can contain full filesystem paths to model files (`modelDir/model.int8.onnx`, `voices.bin`, etc.) | none exists | **E** |
| Android | `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/reader/speech/KokoroTTSController.kt:168` | `Log.e("KokoroTTS", "Error synthesizing chunk", e)` | `e`: `java.lang.Exception` thrown during `tts?.generate(chunk, ...)` or `track.write(...)`; can contain or repeat the reader's story text chunk being synthesized (`chunk`) | none exists | **E** |

## Findings

Findings are ordered by severity: **Credentials and tokens**, then **Usernames**, then **What is read or searched**, then **File names and paths**, followed by **Entity UUIDs** and **Error descriptions marked `.public`**.

### 1. Credentials and Tokens

1. **`kudos-ao3-reader/Services/AO3Client.swift:787`**
   - **Statement**: `Log.network.debug("GET (auth) \(request.url?.absoluteString ?? "?", privacy: .public)")`
   - **What it holds**: Full URL of authenticated GET requests (`request.url?.absoluteString`). Query parameters can carry sensitive session state or query tokens.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private`.

2. **`kudos-ao3-reader/Services/AO3Client.swift:904`**
   - **Statement**: `Log.network.debug("POST (auth) \(request.url?.absoluteString ?? "?", privacy: .public)")`
   - **What it holds**: Full URL of authenticated POST requests (`request.url?.absoluteString`). Can contain tokens or action parameters in query strings.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private`.

### 2. Usernames

1. **`kudos-ao3-reader/Services/AO3Client.swift:787`**
   - **Statement**: `Log.network.debug("GET (auth) \(request.url?.absoluteString ?? "?", privacy: .public)")`
   - **What it holds**: Full URL of authenticated requests, which routes to endpoints formatted as `/users/:username/readings`, `/users/:username/bookmarks`, `/users/:username/subscriptions`, and `/users/:username`. The user's AO3 username is directly logged into OSLog as public plaintext.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private` (or log only request path pattern `"GET (auth) /users/:login/..."`).

### 3. What is Read or Searched

1. **`kudos-ao3-reader/Services/AO3Client.swift:293`**
   - **Statement**: `Log.network.debug("GET \(url.absoluteString, privacy: .public)")`
   - **What it holds**: `url.absoluteString` for all unauthenticated GET requests. This includes search queries (`/works?work_search[query]=...`), tag filter URLs (`/tags/.../works`), author URLs, and work reading pages (`/works/:id`). Exposes the user's complete search terms, reading choices, and tag interests as public plaintext.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private`.

2. **`kudos-ao3-reader/Services/AO3SparseWorkEnricher.swift:57`**
   - **Statement**: `Log.network.notice("Sparse work \(work.id, privacy: .public) could not be enriched: \(error.localizedDescription, privacy: .public)")`
   - **What it holds**: `work.id` (`AO3WorkSummary.id`), which is an AO3 work ID for a work the user is currently browsing, opening, or enriching, plus `error.localizedDescription` which can repeat the work URL.
   - **Smallest fix**: Change `work.id, privacy: .public` to `work.id, privacy: .private(mask: .hash)` and `error.localizedDescription` to `privacy: .private`.

3. **`kudos-ao3-reader/Services/WorkMetadataRefresh.swift:63`**
   - **Statement**: `Log.network.notice("Metadata refresh failed for work \(id, privacy: .public): \(message(for: error), privacy: .public)")`
   - **What it holds**: `id` (`Int`), the AO3 work ID of a work saved in the user's library undergoing background metadata refresh.
   - **Smallest fix**: Change `id, privacy: .public` to `id, privacy: .private(mask: .hash)` and `message(for: error), privacy: .public` to `privacy: .private`.

4. **`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/reader/speech/KokoroTTSController.kt:168` (Android)**
   - **Statement**: `Log.e("KokoroTTS", "Error synthesizing chunk", e)`
   - **What it holds**: Exception `e` thrown during `tts?.generate(chunk, ...)` or `track.write(...)`. In Sherpa-ONNX text synthesis, exceptions can include or repeat the input text `chunk` (the private fanfiction story text currently being read aloud by TTS). Android logcat has no privacy masking.
   - **Smallest fix**: Drop `e` from logcat: `Log.e("KokoroTTS", "Error synthesizing chunk")`.

### 4. File Names and Paths

1. **`kudos-ao3-reader/Services/ImportedDocumentConverter.swift:110`**
   - **Statement**: `Log.library.info("Import sniffed \(format.rawValue, privacy: .public) for \(url.lastPathComponent, privacy: .public)")`
   - **What it holds**: `url.lastPathComponent`, the file name of a user-imported document (e.g. `My Favorite Fanfic.epub` or imported file name), logged as public plaintext.
   - **Smallest fix**: Change `url.lastPathComponent, privacy: .public` to `url.lastPathComponent, privacy: .private`.

2. **`kudos-ao3-reader/Services/KudosBackup.swift:139`**
   - **Statement**: `Log.library.error(""" Backup entry \(name, privacy: .public) failed its CRC-32 check; ... """)`
   - **What it holds**: `name`, the entry path in the backup archive (`Originals/<filename>`, `Works/<title>.epub`, `Fonts/<name>`), which exposes original user file names and work titles as public text.
   - **Smallest fix**: Change `name, privacy: .public` to `name, privacy: .private`.

3. **`kudos-ao3-reader/Services/KudosBackupExport.swift:133`**
   - **Statement**: `Log.library.error("Backup skips unreadable font \(name, privacy: .public).")`
   - **What it holds**: `name` (`font.fileName`), the file name of a custom user-imported font.
   - **Smallest fix**: Change `name, privacy: .public` to `name, privacy: .private`.

4. **`kudos-ao3-reader/Services/KudosBackupExport.swift:137`**
   - **Statement**: `Log.library.error("Backup skips font \(name, privacy: .public): \(reason, privacy: .public)")`
   - **What it holds**: `name` (`font.fileName`), custom font file name; and `reason`, font validation error description.
   - **Smallest fix**: Change `name, privacy: .public` and `reason, privacy: .public` to `privacy: .private`.

5. **`kudos-ao3-reader/Services/KudosBackupExport.swift:143`**
   - **Statement**: `Log.library.error("Backup skips font \(name, privacy: .public): total reached.")`
   - **What it holds**: `name` (`font.fileName`), custom font file name.
   - **Smallest fix**: Change `name, privacy: .public` to `name, privacy: .private`.

6. **`kudos-ao3-reader/Services/FolderSyncService.swift:627`**
   - **Statement**: `Log.library.error("Library folder sync failed: \(message, privacy: .public)")`
   - **What it holds**: `message` (`error.localizedDescription`), filesystem error from folder sync containing the full local directory path and file names.
   - **Smallest fix**: Change `message, privacy: .public` to `message, privacy: .private`.

7. **`kudos-ao3-reader/Services/FolderSyncService.swift:533`**
   - **Statement**: `Log.library.notice("Legacy sync package fold failed: \(error.localizedDescription, privacy: .public)")`
   - **What it holds**: `error.localizedDescription`, filesystem error containing local sync folder paths.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private`.

8. **`/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/reader/speech/KokoroTTSController.kt:98` (Android)**
   - **Statement**: `Log.e("KokoroTTS", "Failed to initialize engine", e)`
   - **What it holds**: Exception `e` from `OfflineTts` initialization. If model/voice files are missing or corrupt, exception details repeat full filesystem paths on the device.
   - **Smallest fix**: Drop `e` or log only `e.javaClass.simpleName` without stack trace.

9. **Filesystem and EPUB file error descriptions marked `.public` (iOS)**
   - Cocoa file errors (`NSError`) from reading, writing, copying, or parsing EPUB files frequently embed the target file path in their `localizedDescription`:
     - `kudos-ao3-reader/Features/Reader/ReaderView.swift:509`: `Log.epub.error("Couldn't open EPUB: \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Features/ReaderReadium/ReadiumBook.swift:570`: `Log.epub.error("Couldn't open EPUB (Readium): \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Services/WorkImporter.swift:57`: `Log.library.error("Couldn't save imported EPUB: \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Services/WorkImporter.swift:107`: `Log.library.error("Couldn't save imported EPUB: \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Services/WorkImporter.swift:596`: `Log.library.error("Couldn't copy imported EPUB: \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Services/KudosBackup.swift:2514`: `Log.library.notice("Skipped an invalid backup EPUB: \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Services/UserDocumentImport.swift:119`: `Log.library.error("Couldn't preserve the original import: \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Services/WorkConversionRecord.swift:58`: `Log.library.error("Couldn't record the conversion version: \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroPackInstaller.swift:50`: `Log.tts.error("Kokoro ANE install failed: \(error.localizedDescription, privacy: .public)")`
     - `kudos-ao3-reader/Features/ReaderReadium/KokoroCastPreflight.swift:104`: `Log.tts.error("Pre-flight could not ready the Kokoro manager: \(error.localizedDescription, privacy: .public)")`
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private` on each statement.

### 5. Entity UUIDs (Collections, Queues, Works)

While UUIDs are random identifiers, they uniquely identify personal user records across backups and sync:
1. **`kudos-ao3-reader/Services/KudosBackup.swift:2575`**: `Log.library.notice("Preserving ambiguous collection \(archived.id.uuidString, privacy: .public)")` — `archived.id.uuidString` is the UUID of a user's collection.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private(mask: .hash)`.
2. **`kudos-ao3-reader/Services/KudosBackup.swift:2808`**: `Log.library.notice("Reviving queue \(archivedQueueID, privacy: .public) because backup is newer than tombstone")` — `archivedQueueID` is the UUID of a user's reading queue.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private(mask: .hash)`.
3. **`kudos-ao3-reader/Services/KudosBackup.swift:2813`**: `Log.library.notice("Preserving queue \(archivedQueueID, privacy: .public) because tombstone conflict is ambiguous")` — `archivedQueueID` is the UUID of a user's reading queue.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private(mask: .hash)`.
4. **`kudos-ao3-reader/Services/KudosBackup.swift:2834`**: `Log.library.notice("Preserving existing queue \(archived.id.uuidString, privacy: .public) despite tombstone conflict")` — `archived.id.uuidString` is the UUID of a user's reading queue.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private(mask: .hash)`.
5. **`kudos-ao3-reader/Services/PersistenceSync.swift:371`**: `Log.library.notice("EPUB asset missing for work \(work.id.uuidString, privacy: .public)")` — `work.id.uuidString` is the UUID of a local saved work.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private(mask: .hash)`.
6. **`kudos-ao3-reader/Services/ReadingQueueService.swift:531`**: `Log.library.error("Queue preserve failed for \(work.id.uuidString, privacy: .public): \(message, privacy: .public)")` — `work.id.uuidString` is the UUID of a local saved work.
   - **Smallest fix**: Change `privacy: .public` to `privacy: .private(mask: .hash)`.

### 6. Network & Client Error Descriptions Marked `.public`

Underlying error messages marked `.public` can repeat server responses, error URLs, entity attributes, or database store paths:
1. **`kudos-ao3-reader/Services/AO3Client.swift:365`**: `error.localizedDescription` (URLError description; embeds request URL) -> `privacy: .private`
2. **`kudos-ao3-reader/Services/DownloadQueue.swift:182`**: `error.localizedDescription` (download error; can embed request URL/path) -> `privacy: .private`
3. **`kudos-ao3-reader/Features/Home/HomeView.swift:593`**: `UserFacingError.message(for: error)` -> `privacy: .private`
4. **`kudos-ao3-reader/Features/Search/FandomListView.swift:436`**: `error.localizedDescription` -> `privacy: .private`
5. **`kudos-ao3-reader/Features/Search/FandomListView.swift:445`**: `error.localizedDescription` -> `privacy: .private`
6. **`kudos-ao3-reader/Features/Search/MediaBrowserView.swift:872`**: `error.localizedDescription` -> `privacy: .private`
7. **`kudos-ao3-reader/Services/PersistenceSync.swift:207`**: `message` (migration error message) -> `privacy: .private`
8. **`kudos-ao3-reader/Services/PersistenceSync.swift:212`**: `message` (database save error message) -> `privacy: .private`
9. **`kudos-ao3-reader/Services/ReadingQueueService.swift:531`**: `message` (queue preservation error) -> `privacy: .private`
10. **`kudos-ao3-reader/Services/ReadingQueueService.swift:586`**: `error.localizedDescription` (series fetch error) -> `privacy: .private`
11. **`kudos-ao3-reader/Services/WorkAvailability.swift:68`**: `reason` (availability check reason) -> `privacy: .private`
12. **`kudos-ao3-reader/Utilities/ModelContext+SaveBestEffort.swift:42`**: `error.localizedDescription` (SwiftData save error) -> `privacy: .private`
13. **`kudos-ao3-reader/Services/AO3AuthService.swift:511`**: `error.localizedDescription` (Keychain error) -> `privacy: .private`
14. **`kudos-ao3-reader/Services/AO3AuthService.swift:622`**: `error.localizedDescription` (Keychain error) -> `privacy: .private`
15. **`kudos-ao3-reader/Services/AO3AuthService.swift:673`**: `error.localizedDescription` (Keychain error) -> `privacy: .private`
16. **`kudos-ao3-reader/Services/AO3AuthService.swift:888`**: `error.localizedDescription` (Keychain error) -> `privacy: .private`
17. **`kudos-ao3-reader/Services/AO3AuthService.swift:967`**: `error.localizedDescription` (Keychain error) -> `privacy: .private`
18. **`kudos-ao3-reader/Services/AO3AuthService.swift:1023`**: `error.localizedDescription` (Keychain error) -> `privacy: .private`
19. **`kudos-ao3-reader/Services/AO3AuthService.swift:1059`**: `error.localizedDescription` (Keychain error) -> `privacy: .private`
20. **`kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroTTSService.swift:138`**: `error.localizedDescription` -> `privacy: .private`
21. **`kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroTTSService.swift:324`**: `error.localizedDescription` -> `privacy: .private`
22. **`kudos-ao3-reader/Features/ReaderReadium/CoreMLKokoroTTSService.swift:420`**: `error.localizedDescription` -> `privacy: .private`
23. **`kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechController.swift:477`**: `error.localizedDescription` -> `privacy: .private`
24. **`kudos-ao3-reader/Features/ReaderReadium/ReaderSpeechController.swift:522`**: `error.localizedDescription` -> `privacy: .private`
25. **`kudos-ao3-reader/Features/ReaderReadium/SherpaKokoroTTSService.swift:145`**: `error.localizedDescription` -> `privacy: .private`
26. **`kudos-ao3-reader/Services/FolderSyncBackgroundTask.swift:53`**: `error.localizedDescription` -> `privacy: .private`
27. **`kudos-ao3-reader/Services/PDFWorkConverter.swift:301`**: `error.localizedDescription` -> `privacy: .private`

## Counted

### Statements Read

- **iOS (`kudos-ao3-reader/`)**: **124** log statements total
  - **85** statements include non-constant interpolated values or arguments (all listed in the table above)
  - **39** statements are static constant strings without interpolation
  - All 124 statements use the unified `Log.<category>.<level>(...)` logging interface; 0 statements use `print(`, `NSLog(`, `os_log(`, or standalone `Logger` instances
- **Android (`/Users/cidy02/kudos-android-lane/android/app/src/main/`)**: **2** log statements total
  - **2** statements include non-constant values (both `Log.e(...)` calls in `KokoroTTSController.kt` listed in the table above)
  - **0** statements are static constant strings
  - 0 statements use `println(`, `Timber`, or `printStackTrace(`

### Files Read

- **iOS**: All **406** `.swift` source files under `kudos-ao3-reader/`
- **Android**: All **460** `.kt` Kotlin source files under `/Users/cidy02/kudos-android-lane/android/app/src/main/java/`, and **1** C source file (`/Users/cidy02/kudos-android-lane/android/app/src/main/cpp/kudos_mupdf.c`)

### Files Not Read

The following files and directories were outside the scope of executable application log auditing or did not contain application code:

1. **iOS worktree (`kudos-ao3-reader/`) non-Swift / non-code files**:
   - Header and bridge files: `kudos-ao3-reader/Kudos-Bridging-Header.h`, `kudos-ao3-reader/Reading/KudosMuPDF.h`, `kudos-ao3-reader/Reading/KudosMuPDF.m` (inspected; no log statements present)
   - Asset catalogs and static resource bundles: `kudos-ao3-reader/Assets.xcassets/`, `kudos-ao3-reader/Catalog/`, `kudos-ao3-reader/FandomCatalog/`
   - Configuration files: `kudos-ao3-reader/Kudos.entitlements`, `kudos-ao3-reader/Info.plist`
   - Xcode project file: `AO3_App_OpenSource.xcodeproj/`
   - Unit tests: `KudosTests/` (112 test suite files, outside `kudos-ao3-reader/`)
   - Repository scripts and docs: `Scripts/`, `docs/`

2. **Android repository (`/Users/cidy02/kudos-android-lane/android/app/src/`)**:
   - Test directory: `/Users/cidy02/kudos-android-lane/android/app/src/test/` (unit and mock tests, outside `src/main/`)
   - Debug build variant: `/Users/cidy02/kudos-android-lane/android/app/src/debug/` (`DesignCatalogScreen.kt` and test fixtures in `assets/fixtures/`)
   - Release build variant: `/Users/cidy02/kudos-android-lane/android/app/src/release/`
   - Android XML resources and manifests: `/Users/cidy02/kudos-android-lane/android/app/src/main/res/` and `AndroidManifest.xml`

## Triage (Claude, 2026-10-08)

Every listed line was opened and read. Fixed on iOS in **T-369** (`2d968a55`): the three
request-address statements, three work ids (hashed), an imported file's name, backup entry
and font names, and four failure reasons that can quote a path. Left public on purpose:
local database UUIDs, counts and status codes, and failure reasons from sign-in, speech and
the fandom lists (the app's own fixed sentences).

One rule in the brief was wrong: a value with no marker is private only for strings and
objects; **numbers default to public**. Two work ids were caught by that.

Android has two log statements in all (confirmed by a search, and there is no HTTP logging):
the one that could quote the text being read aloud now logs only the kind of failure.
