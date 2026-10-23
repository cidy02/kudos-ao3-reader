# §7 parity matrix: proposed marks as of 2026-10-22 (draft)

A draft to paste over LIVING-PROMPT.md §7, whose marks were last set on 10-11 (2 ✅, 20 🟦, 5 🟨).
**Proposed: 8 ✅, 19 🟦, 0 🟨.** Every row is built; no row is "in progress" any more. Each 🟦
row is waiting only on A82's screens and the owner checks named in it.

**Rule** (§7): a row turns ✅ when its pages have been beside the iPhone's in Dark, Light, Sepia,
OLED and at 2.0×, with what was found fixed or written down. Here that means every one of the
row's screens in A81 (`audits/A81-result.md`) was compared in all five columns by a side-by-side
audit and nothing is left open. A screen still in A82 (`audits/A82-shots.md`, being compared now)
keeps its row at 🟦.

**Two things this draft does not settle:**
- The passes compared the two phones with each other, not with the artboards (§0 item 1 says
  "against the iOS screen and its artboard"). The iPhone was checked against the artboards by its
  own polish loop (`INVENTORY.md`, column S).
- Owner checks (Read Aloud heard, real AO3 sign-in and writes, two-phone sync, the Mac) are
  listed per row. They do not stop a row's screens from being ✅.

**How to read the Android status cell:** proposed mark (old mark) · the audits that compared the
row's screens · **Open:** what keeps it from ✅ · **A84:** ⟨placeholder for Grok's code
comparison⟩ · a note.

**Audits by pair.**
- A69/A70 shot batch 1 (22 main screens) and A70b the 14 Settings pages; A70c retook 15.
- A71 shot batch 2 (29 screens). A72 shot all 65.
- A76 shot all 67 (+ `compose`, `bugreport`): 65 match, and the 2 minors were fixed in `8667ab4d`.
- A79 re-shot the 15 screens changed after A76: all match.
- A80 compared four new pairs.
- What a pass decided not to report (demo data, decided differences) is A76's "Decided, not to
  report" list and `DECISIONS.md`.

| Area | Artboards | iOS reference | Android status | Owner |
|---|---|---|---|---|
| Base reconciliation | — | T-245 | ✅ (was ✅) · 0c · **Open:** none · **A84:** ⟨ ⟩ · No screens of its own. | Claude |
| Theme tokens / SubjectPalette | all | UIComponents/SubjectSurface.swift, CarouselCardStyle.swift | 🟦 (was 🟦) · every pass A69–A80, in all four themes (accent text readable on Dark/OLED after Q19, `c17d376d`; A79 checked the Dark/OLED glyphs) · **Open:** cross-cutting, so it closes with the last screens, A82's 70 · **A84:** ⟨ ⟩ · Nothing token-wide open in A76/A79/A80. | — |
| Shared components | all | UIComponents/* | 🟦 (was 🟦) · every pass A69–A80 (figure strip, chips, segmented control, pager capsule, cardRow fixed in `701595c9`, `1bbefdfd`) · **Open:** closes with A82's 70 screens · **A84:** ⟨ ⟩ · Placeholder rows (U3, `98586ab2`) seen mid-load in four themes and at 2×, on Android only. | — |
| Shell / tabs / demo mode | — | App/*, DemoLibrary | ✅ (was 🟦) · the five tab roots `home`, `library`, `browse`, `search`, `account`: A69, A70, A72, A76, A79 · **Open:** none · **A84:** ⟨ ⟩ · The navigation bar and icon buttons are Material by decision (owner 2026-10-04; Q12's three items stay open). Predictive back (U1, `6a14cec3`) is Android's own. Both apps open any screen with `shot:<name>`. | — |
| Home | 1b, 1ad, 1ae, 1af, 1ag | Features/Home | ✅ (was 🟦) · `home` A69, A70, A72, A76, A79; `hsec_reading`, `hsec_updated` A71, A72, A76 · **Open:** none (A81: 3 screens, all paired) · **A84:** ⟨ ⟩ | — |
| Library dashboard + sections | 1c, 1d, 1ah, 1ai, 1aj, 1ak, 1bc, 1bd, 1ay | Features/Library | 🟦 (was 🟨) · `library` A69–A79; the six sections `sec_*` A71, A72, A76 (`sec_history`, `sec_favorites` also A79); `libraryfilters` A80 (minor: height, fixed `cde116dd`) · **Open:** A82 `libpicker`; `libraryfilters` re-paired after its fix (seen on the emulator only, five columns) · **A84:** ⟨ ⟩ · The filter checkmark's red is the decided section wash (A80 triage). | — |
| Reading queues | 1h, 1i, 1j, 1bg, 1bh | ReadingQueue*.swift, NewReadingQueueSheet, QueueCardMenu | 🟦 (was 🟦) · `queues` A69–A79; `queue` A71, A72, A76, A79 · **Open:** A82 `queuesettings`, `newqueue`, `editqueue`, `addworks`, `queuetag`, `queuetags`, `queuetagedit`, `bulktag`, `addtoqueue`, `queuestorage` · **A84:** ⟨ ⟩ · 10 of the area's 12 screens were never paired. | — |
| Local collections | 1bk, 1e? | Collections.swift, NewCollectionSheet | 🟦 (was 🟦) · `collections` A69–A79; `collection` A71, A72, A76, A79 · **Open:** A82 `collectiondetails`, `newcollection`, `collectionreorder`, `addtocollection` · **A84:** ⟨ ⟩ · Android's Add to Collection is still a dialog (no restyle on record, `REDESIGNED-WITHOUT-MOCKUP.md`). | — |
| Recently Deleted | 1bj | RecentlyDeletedView | ✅ (was 🟦) · `deleted` A69, A70, A72, A76, A79 · **Open:** none (A81: 1 screen) · **A84:** ⟨ ⟩ | — |
| Reading Insights | 1bi | ReadingInsightsView | ✅ (was 🟦) · `insights` A69, A70, A72, A76 · **Open:** none (A81: 1 screen) · **A84:** ⟨ ⟩ · Words per hour counts each sitting's reading (Q27, both apps). | — |
| Browse | 1g, 1al, 1am, 1an | Features/Browse, Search/FandomList*, MediaBrowserView | 🟦 (was 🟦) · `browse` A69, A70, A72, A76 · **Open:** A82 `fandomlist`, `fandomworks`, `tagworks`, `fandomfilter` · **A84:** ⟨ ⟩ · Jump Back In no longer arrives scrolled out of sight (`cd04b55a`, A72). | — |
| Search + filters + save search | 1k, 1ao–1ax | Features/Search | 🟦 (was 🟦) · `search` A69, A70, A72, A76; `searchfilters` A80 (match) · **Open:** A82 `savesearch`, `pagejump`, `languagepicker`, `tagpicker` · **A84:** ⟨ ⟩ · The language and tag pickers are inline on Android's filter sheet, not pages of their own (A81). | — |
| Work detail + My copy | 1a | Features/WorkDetail | 🟦 (was 🟦) · `workdetail` A71, A72, A76, A79; `mycopy` A71, A72, A76 · **Open:** A82 `downloaddate`, `seriespreserve`, `bookmarkform`; owner: kudos, bookmark and subscribe against real AO3 · **A84:** ⟨ ⟩ | — |
| Reader (Readium, settings, annotations, read aloud) | — | ReaderReadium/* | 🟦 (was 🟨) · `reader` A71, A72, A76 · **Open:** A82 `readercontents`, `readerfind`, `readerdisplay`, `readernote`, `pronunciations`, `pronunciationedit`, `customizetheme`. Not comparable: the Read Aloud settings sheet (no Android sheet; its settings are on Settings › Listening; a gap by the 10-22 log, not yet in DECISIONS) and the speech developer settings (decided out). Owner: **Read Aloud never heard on Android**; pronunciation corrections are not yet played (voice pack). Q12 (glass reader controls) is open · **A84:** ⟨ ⟩ · Everything on iOS's list is built (3fs, 3ft, 3gd, 3gf; immersive reading U1). | — |
| Comments | 1f, 1ba, 1be, 1bf | Features/Comments | 🟦 (was 🟦) · `comments` A71, A72, A76; `compose` A76 (minor, fixed `8667ab4d`), A79; `thread` A80 (differs, fixed `0ddb694f`, `cde116dd`) · **Open:** A82 `formattingtray`, `chapterpicker`; `thread` re-paired after its fixes (seen on the emulator only); owner: posting, editing and deleting on real AO3 · **A84:** ⟨ ⟩ · The kept-copy line says offline or unreachable (both apps). | — |
| Account hub + signed out | 1m, 1bt, 1n | Features/Account | ✅ (was 🟦) · `account` A69, A70, A72, A76, A79; `login` A80 (differs; decided, not changed: "Use alternative method", the accent, Cancel at 2×, in DECISIONS) · **Open:** none on screen; owner: **signing in on the real site** (never done) · **A84:** ⟨ ⟩ · Signed out is the same view (A81). | — |
| Marked for Later / Bookmarks / History / Subscriptions | 1o, 1q, 1t, 1p | Features/Bookmarks | ✅ (was 🟦) · `later`, `bookmarks`, `history`, `subs` A69, A70, A72, A76 · **Open:** none on screen; owner: Unmark, Unsubscribe and bookmark edits on real AO3 (fixtures only so far) · **A84:** ⟨ ⟩ | — |
| Inbox | 1l | AccountInbox* | 🟦 (was 🟦) · `inbox` A69, A70, A72, A76 · **Open:** A82 `inboxfilter` · **A84:** ⟨ ⟩ | — |
| Author pages / Works / Series / Dashboard | 1u, 1v, 1w, 1y, 1az | Features/Authors | 🟦 (was 🟦) · `author`, `myseries` A71, A72, A76 (`myseries` A79); `works`, `dashboard` A69, A70, A72, A76 · **Open:** A82 `authorabout`, `seriesdetail`, `seriesedit`, `seriesreorder`, `seriesremove`, `authorworksfilter`. Not comparable: the author page pushed on Bookmarks (no Android page: the dashboard opens the Bookmarks list, A81; a gap by the 10-22 log, not yet in DECISIONS). Owner: series edits on real AO3 · **A84:** ⟨ ⟩ · Own Works and Series as the iPhone, with Android's totals kept (Q24). | — |
| AO3 collections | 1r, 1s, 1bl, 1bm, 1bx, 1ci, 1cg | Account/AO3Collection* | 🟦 (was 🟦) · `ao3colls`, `ao3coll` A69, A70, A72, A76; `colsettings`, `colmaint`, `colmod` A71, A72, A76 · **Open:** A82 `colitems`, `colsfilter`; owner: the form, moderation and maintainers against real AO3 (never run; Q13–Q15) · **A84:** ⟨ ⟩ · A72's `ao3coll` difference was an iPhone parsing bug, fixed (T-426). | — |
| Challenges | 1by, 1bz, 1ca, 1cb, 1cc, 1cd, 1ce, 1cf, 1ch | Features/Challenges | 🟦 (was 🟨) · `chsettings`, `chsignups`, `chmysignup`, `chassign` A71, A72, A76; `chprompts` A71, A72, A76 (minor, fixed `8667ab4d`), A79 · **Open:** A82 `chsettingsedit`, `chsignupdetail`, `prompttags`, `tagset`, `tagseteditor`; owner: sign-up, claim and settings writes against real AO3 (fixtures only; Q16) · **A84:** ⟨ ⟩ · Each settings read now asks only the form the collection's kind names (`3e23e694`, T-429). | — |
| Writing (drafts, work edit, chapters, tags, series) | 1x, 1bn–1bw | Features/Writing | 🟦 (was 🟨) · `drafts` A69, A70, A72, A76; `workedit`, `draftedit` A71, A72, A76 · **Open:** A82 `writingpreview`, `chapters`, `chapterform`, `edittags`, `tagseditor`, `texteditor`, `recovery`, `seriespicker`, `collectionsgifts`, `creatorspicker`, `parentpicker`, `bulkedit`, `bulktagstate`, `bulknames`; owner: Save, Post and Delete against real AO3 (fixtures only; Q17); the editor's widget never measured on a phone · **A84:** ⟨ ⟩ · 14 of the area's 16 screens were never paired. Q32 ("Discard changes?") is open. | — |
| AO3 Preferences | 1z, 1bb | AO3PreferencesView | 🟦 (was 🟦) · `prefs` A69, A70, A72, A76 · **Open:** A82 `prefhelp`; owner: saving preferences on real AO3 · **A84:** ⟨ ⟩ | — |
| Settings hub + pages | 1ab, 1ac | Settings/* | 🟦 (was 🟦) · `settings` A69, A70, A72, A76; the 14 pages `s_*` A69, A70b, A72, A76 (`s_sync` A79) · **Open:** A82 `privacydata`, `availability`, `pairing`, `revokedevice`, `backupimport`. Not compared by decision: Scan a QR Code and Sync Details (DECISIONS 2026-10-11). Owner: pairing two real phones · **A84:** ⟨ ⟩ · Android's extras are on A76's excluded list: System theme, Backup's notes and Deletion signing (Q9), Software Update. | — |
| More on AO3 | 1aa | AccountMoreOnAO3View | 🟦 (was 🟦) · `more` A69, A70, A72, A76 · **Open:** the in-app AO3 web browser cannot be compared offline (A81: the demo does not serve those pages); owner check on the real site, or record it as out of the pass · **A84:** ⟨ ⟩ · Every row opens something (`a5cfb152`, reading R1). | — |
| Onboarding / Support / About | — | Features/Onboarding, Support, Settings/AboutView | 🟦 (was 🟨) · `welcome`, `synconb`, `whatsnew` A71, A72, A76; `bugreport` A76 · **Open:** A82 `aboutkudos`; owner: the first sync-folder setup with a real cloud folder (Q5) · **A84:** ⟨ ⟩ · No artboards; restyled after the iPhone (`REDESIGNED-WITHOUT-MOCKUP.md` R24–R27). | — |
| Data parity (model, backup, sync) | — | Models, Services | ✅ in tests (was ✅ in tests) · each app against the other's archive and sync folder (5a, 5b), fixtures carrying fonts, pronunciations and deletion dates both ways (3ge `4a63e64b`, iOS T-423), A75's rules (`35c986f0`) · **Open:** owner: **two real phones** through a cloud folder (Q4–Q6), the Mac reading-position check (A12-1), and data questions Q7, Q8, Q18, Q21, Q33 · **A84:** ⟨ ⟩ · Never tried on devices. | — |

## Screens no pass can compare yet (6, A81)

- **Read Aloud settings sheet** (Reader): no Android sheet. A gap: the Living Prompt's 10-22 log counts it, but there is no DECISIONS entry yet.
- **Speech developer settings** (Reader): not ported, a decision.
- **Author page pushed on Bookmarks** (Author pages): no Android page. A gap, as above.
- **Scan a QR Code** (Settings): Android only shows a code, a decision.
- **Sync Details** (Settings): kept out, a decision.
- **In-app AO3 web browser** (More on AO3): needs AO3.
