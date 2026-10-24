# Kudos Android: owner summary

*Final, 2026-10-24 08:10 (Claude-CLI), for the sprint that began 2026-10-20 12:30. Android parity is done.*

**In one paragraph:**
- **Screens:** Android matches the iPhone on the 67 screens compared by 10-22.
  - The 70 screens never put side by side before were compared (A82), fixed on both apps, and compared twice more: A88 (all 72 new pairs, two reviewers per half) and A88c (the 41 re-shot pairs, two reviewers).
  - A88c's fixes have landed on both apps. A97 checked 38 re-shot pairs; every earlier fix held. A96, A98, round 2 and round 3 (A100) dealt with the smaller differences. D7, D8 and the 10-24 entry in `DECISIONS.md` record the accepted platform differences.
  - **The parity matrix:** all 27 rows are verified (✅). Round 3 closed the last two: Library's filter sheets take the app's colour (brown in Sepia), and Author pages' Load More reads in primary ink (A100, `432c34f8`).
  - **One iPhone item is open (I20, Codex):** the iPhone's Library filter sheet is purple in every theme, the first work's colour, which iOS's own colour rules don't allow (Sepia should be brown). Android follows the rules. If I20 finds the purple intended, Android will follow it instead.
- **Tests:** gate-31 at Android `432c34f8`: 3,461 tests, none failed, one skipped. Lint has no new warnings, four gone. A100's three new checks fail with its fixes reverted.
- **Data:** parity holds in tests both ways, but has never been tried on two real phones.
- **What's left for Android:** nothing from the loop. Your checks remain: hearing Read Aloud on a phone, the real AO3 site (we never sign in), two phones syncing through a cloud folder, one Mac check, merges to `main`, and the 26 questions listed as open, each with a default. Two separate asks are below: Device Hub and five idle simulators.

Nothing has been merged to `main`.

## 1. Where it stands, against "Done"

"Done" (Living Prompt §0) has five Android items, plus the iOS list (§5c) and the bug hunt (§5d).

1. **Every screen verified against the iPhone in Dark, Light, Sepia, OLED and the largest text: done. All 27 rows ✅ after round 3.**
   - **The first 67:** shot on both phones in five columns, fixed, and shot again (A69 to A80). A76 matched 65 of 67, and its two small differences are fixed. A79 rechecked the 15 screens changed since: all match.
   - **The 70 never paired (A82):** shot in two halves. The first half was also read in code by Codex (A84a), the second by the CLI session (A84b).
     - First half: 9 match, 5 minor, 21 differ.
     - Second half: 13 match, 4 minor, 18 differ.
     - Fixed on Android in 3gw (`8ffb409d`) and 3gx (`e0162833`), and on the iPhone in T-434 to T-436.
   - **Two screens Android lacked now exist:** the reader's Read Aloud sheet (long-press the Read Aloud button) and the dashboard's See all bookmarks (`933b9bed`).
   - **Not comparable (4):** the speech developer settings, Scan a QR Code and Sync Details are out by decision. The in-app web browser needs AO3.
   - **Pass scope:** the passes compared the two phones with each other. The iPhone was checked against the artboards by its own loop.

   - **A88, all 72 new pairs shot again after the fixes** (A82's 70, plus the Read Aloud sheet and See all bookmarks). Two reviewers looked at each half, Gemini and the CLI session; the merged view is `audits/A88-triage.md`.
     - 31 of the 35 earlier differences they could judge are gone.
     - What they found is fixed:
       - **Android, 3gz** (`46a50158`): queue tags' rows, a fandom's works page naming its fandom, colour swatches per theme, the formatting tray's Done, the chapter picker as one card, and the page picker's colours.
       - **Android, 3ha** (`f8d65081`, with A92's fixes): the series card's Restricted, bookmarks and date, challenge settings' sign-up count and pinned Save, bulk names, author bookmarks, sheet colours, availability's stray rule, privacy's wash.
       - **iPhone:**
         - long sheet titles get a short bar title and the full name on the sheet (I12, T-437);
         - whole bylines in Add Works (I13, T-438);
         - the collections filter's Reset, a collection item's creator name, and three debug routes (I14, T-439);
         - the parent work's URL field (I15, T-440), corrected again in T-443 after the re-shoot still showed a hyphen at the largest text.
     - About a quarter of the Android columns were capture faults ("isn't responding", the wrong screen). The re-shoot now starts every screen warm.

   - **A88c, the 41 re-shot pairs** (Android started warm; the iPhone's ten that its fixes touched). Two reviewers, each on their own: the CLI session found 22 match, 15 minor, 4 differ; Gemini found 33, 6, 2. The merged view is at the foot of `audits/A88-triage.md`.
     - Every A88 difference in the set is gone or decided, and the capture faults are gone except four columns.
     - **Found on Android, since fixed:** the wash restarting under a pinned field (there since 10-07), darker sheet cards in Sepia, wrong accents, Add looking enabled with no name, and the editor's cut bar title.
     - **Found on the iPhone, since fixed in T-441:** Sample Text cut at the largest text, the unreadable current-speed pill in Light and Sepia, and pronunciation shots stopping on Listening.
     - **Landed:**
       - **3hb (Codex), pairing and the fandom list** (`6c002b44`): the seam, sheet cards, accents, Add, editor title and Customize Theme; pairing's intro and icon-row cards with expanding Advanced; Group variants' tint and icon, and card rows.
       - **Find and Note keep their keyboard focus**, as on iOS. That item was withdrawn: the iPhone shots had a hardware keyboard.
       - **A88d's two fixes** (`76c7e273`): the preferences help sheet's close control and cards, and bulk names' disabled Add.
       - **3hc, finished as 3hc2, and 3hd** (`5455f869`): bylines and collection reorder; fields now scroll away under one wash, more pagers take the page's colour, reader cards stay glass in Light and opaque in the other themes, Customize Theme stays opaque. Card dates stay as they are (Q28).
       - **The queue test's teardown race** (`5c6b0f1c`): it waits for the action's refresh before closing the database.
     - **Re-shot and checked:** A88d's screens and the later fixes in A97; the iPhone's URL after T-443, in all five columns. Revoke's dialog is accepted (D7), and the formatting tray matches.

   - **A96** (`82626348`): series figures and fandoms have their icons, a linked creator uses the app accent, detailed work cards say "by", and the author's heading reads "Bookmarks".
   - **A97, 38 re-shot pairs:** every 3hb/3hc/3hd/A88d fix held. Claude-CLI found 2 differs, 8 minor and 2 capture problems. Gemini's second read failed on network and quota.
   - **A98** (`c314551f`): the speed pill and Sample Text ink, page-jump ends, filter menus and palettes, challenge colour from its title or slug, short recovery time, New Work first, the chapter glyph and help title. My Works keeps its totals.
   - **A99** (`e347c8d2`): a debug route to Thread made its first real pair possible. It matches in round 2.
   - **Round 2:** A98's fixes hold. The iPhone editor's largest-text fault is fixed in T-445.
   - **Round 3** (A100, `432c34f8`): Library's and Home sections' filter sheets use the app's colour instead of the hero's, and the author pages' Load More is in primary ink. Re-shot in all five columns; Load More's Material label weight is accepted. The iPhone's purple filter sheet is I20 (above).
   - **D7 and D8** (`edf3d2fd`, `a39d9b29`, in `DECISIONS.md`): Material fields and controls, Android's chrome and differing demo data are accepted where nothing is lost. Examples: revoking in a dialog, outlined fields, First/Last as text buttons, the chapter glyph and the short recovery date.

2. **Every owner decision in §6 present on Android: done.** A77 reported 62 present and 10 gaps. Eight were fixed (3go). One is not a fault (Android uses buttons where iOS uses swipes, decided). One is your question 9.

3. **Data parity (model, backup, sync, round trip both ways): done in tests, never tried on two real phones.**
   - Each app restores the other's backups and reads the other's sync folder in tests. The shared fixtures carry fonts, pronunciations and deletion dates both ways (Android `4a63e64b`, iOS T-423).
   - A75 re-checked 195 iOS data rules against Android: 152 were already there. The real gaps are fixed (3gq, `35c986f0`).
   - A reading-queue tag renamed to a name you already use is refused instead of merged, as on the iPhone (`e0162833`, in DECISIONS). On the iPhone, a correction file that can't be read is no longer overwritten (I12, T-437).
   - The sync questions 4–8, 18, 21 and 33 are yours.

4. **Build and tests, no new lint warnings: done.**
   - Gate-31 at `432c34f8`: 3,461 tests, none failed, one skipped (the text-selection magnifier); assemble passes; lint 0 new, 4 gone. The two tests that failed only in gate-30's full run passed in gate-31's.
   - Gate-30 at `c314551f`: 3,455 tests, four full-run failures. Two A98 tests read the theme too early; fixed, then 10/10 in their class. LibraryHistoryScreenTest and NamedSubscriptionsBrowserTest failed only in the full run, then passed alone (15/15 and 8/8). Assemble and release compile pass; lint 0 new, 4 gone.
   - A99's comments tests pass, 79/79. This is a separate run, not another full gate.
   - The 16 tests 3gx held back now run (3gy). Each was a test fault, not an app fault. At 3ha's gate, one was skipped: the text-selection magnifier, which the runner can't draw.
   - 3ha's first full run had 22 failures: sixteen later tests affected by two tests leaving the demo network on, and six still asserting pre-A92 behaviour. Fixed in the tests, not the app.
   - **A84, the code comparison:** Codex read the first 35 A82 screens in both apps (56 P2, 43 P3), and the CLI session the second 35 (18 same, 17 differ: 1 P2, 24 P3). Android's side is fixed in 3gx. The iPhone's side is fixed in I11 (T-436) and I12 (T-437).

5. **An owner summary and `OWNER-DECISIONS-ANDROID.md`: done (this file).** The questions file lists 34: 7 marked answered, 1 withdrawn, 26 listed as open (§3 below). Question 3's default below follows the later owner instruction.

**iOS (§5c): done, except one Mac check.** These landed:
- **10-22:** Comments says why it shows a kept copy (T-430). The editor's Preview and recovery copy no longer stall at AO3's 510,000-character limit (T-431). The prompt meme's settings read asks only the form that matches the collection's kind (T-429). The largest-text fixes you approved (T-425). A debug route for each of the 70 never-paired screens (T-432).
- **10-23:**
  - The recovery copy can be copied whole (T-433).
  - The iPhone's side of A82 (T-434): Sepia surfaces that were white, titles and text cut at the largest size, blank or missing titles, and the About licence's stray asterisks.
  - A87's fixes (T-435).
  - A failed save says so instead of closing as if it worked, in New Queue, Edit Queue, New Collection, a collection's details and the pronunciation editor (T-436).
  - **T-437 (I12):**
    - Long sheet titles (Revoke a device, Add Works) get a short bar title and the full name at the top of the sheet.
    - Pronunciation read, paste and delete errors say so, and a file that can't be read is never overwritten.
    - Add Works counts only what it will add.
    - The comments chapter picker stops spinning when there are no chapters.
  - **T-438 (I13):** Add Works' bylines are whole at the largest text.
  - **T-439 (I14):** the collections filter's Reset, a collection item's creator name, and three debug routes at the largest text.
  - **T-440 (I15, `9dc1e095`):** replaced the parent URL field; the re-shoot still showed a hyphen at the largest text, corrected in T-443 below.
  - **T-441 (I16, `e654c69e`, A88c's iPhone items):**
    - Read Aloud's Sample Text wraps whole at the largest text.
    - The current speed's pill reads in every theme.
    - The largest-text pronunciation shots get past Listening.
  - **T-442 (I17, `24e04efb`):** Comments uses the app's one offline-error list for kept pages and cold failures.
  - **T-443 (`f24572c2`):** the parent URL wraps at any character, without a hyphen; seen in all five columns.
  - **T-444 (I18, `7f479443`):** a paste with a line break keeps editing and undo, VoiceOver gets the placeholder, and a text-size change updates the field.
  - **T-445 (I19, `d3e66077`):** at the largest text the editor keeps room to write: one recovery line, scrolling formatting chips, and Editor help holding both notices.

T-440 to T-442 ran full suites with the known 10 failures. T-443 to T-445 ran their affected suites, not the full suite. T-445 was seen in all five columns; macOS builds.

Left: on a Mac, after the Mac has read further, does the iPhone open at the Mac's place (§3)?

**Bug hunt (§5d): no open P1 or P2 reported.** Findings were checked before acting, which matters: two of Gemini's reviews quoted code that isn't there.
- **A86** (Gemini, on 3gw): six real. The main one: TalkBack couldn't reach the reader Contents' Bookmark and Add Note. All fixed (`47fbc6ec`).
- **A87** (Gemini, on T-433/T-434): three real, all small, fixed in T-435. Two were not faults.
- **A89** (the CLI session, on 3gx before it landed): one P2, opening Display made a second speech engine on the main thread. Six P3s. All fixed in `e0162833`.
- **A90** (Codex): stopped a wrong fix before it landed. Series listings stay read as a guest, as on the iPhone and as AO3's networking rules require.
- **A91** (the CLI session, on I12): no new way to lose a correction and no new AO3 read. Its small fixes went into I12.
- **A88a and A88b** (Gemini and the CLI session, each looking at the same screens on its own): the re-review above. Their verdicts were merged before anything was briefed.
- **A92** (the CLI session, on 3ha before it landed): no P1 or P2 and no new AO3 read. Four small faults: a subtitle showing the collection's short name instead of its title, a sheet grey in Light, a borrowed style flag, and two tests that didn't test what they named. All four are fixed in `f8d65081`.
- **A88c** (Gemini and the CLI session): fixed as above; the keyboard-focus item was withdrawn.
- **A93:** no P1 or P2; five P3s fixed in 3hd. **A94:** the review led to 3hc2, including bylines checked against real iOS identities, not its demo's missing ones.
- **A95:** the empty URL field's reported P1 was not real on the simulator. Its four minor points are fixed in T-444. **A96 to A99 and round 2:** the screen follow-ups above.

## 2. What changed during the sprint (2026-10-20 to now)

**You'll notice these on Android:**
- **Reader:**
  - Highlight marks the passage at once, and Add Note opens the full editor (your Q30).
  - Customize Theme is the iPhone's reading-text sheet (Q29), with its round "Aa" swatches.
  - While you read, the system bars hide; they come back with the reader's controls. Predictive back is on (your approved U1).
  - The contents list has the work's Summary. Its Bookmarks show the saved passage and note. Go, Bookmark and Add Note are swipe actions, and TalkBack can reach them too.
  - Go to page is the iPhone's sheet: a page number "of N", nearby pages, First and Last.
- **Read Aloud:**
  - Long-press the Read Aloud button for a Read Aloud sheet. Display & Themes has the same Listening controls.
  - Pronunciation corrections, as on iOS. Android can't play them yet because the voice pack ignores them, and the page says so.
  - Settings › Listening can download the Kokoro voice, and has Engine and Pitch. Previous and Next move by chapter, and a mini-player stays when the controls hide.
- **All 27 rows:** matched or accepted in all four themes and at the largest text, through A97 and rounds 2 and 3. Examples from the sprint:
  - A series page shows Restricted and every fandom.
  - Reorder rows have drag handles.
  - The queue tag editor reads Name, Merge, Remove.
  - The fandom list keeps Group variants as you left it, and a failed refresh keeps its rows.
  - The fandom filter's Show button stays in view, and closing the sheet cancels your changes.
  - Tag search starts from the first letter, in Refine too.
  - A series opened directly shows Restricted, its bookmarks and date, and its works' zero figures.
  - Challenge settings' Save is a filled button pinned at the foot, and its subtitle counts the sign-ups already read.
  - Author bookmarks have a Bookmarks header and a Load More card, its label in primary ink (A100). Library's and Home sections' filter sheets take the app's colour, not the hero's (A100). Bulk names are one row. Help and recovery sheets are white in Light.
  - A fandom's works page names its fandom as a filter.
  - Colour swatches look as on the iPhone in each theme.
  - The comments formatting tray has Done.
  - The series card has figure and fandom icons; linked creators use the accent, and detailed work cards say "by" (A96).
  - Pairing uses grouped icon rows and expanding Advanced; Group variants has its tinted chip and icon.
  - Read Aloud's current speed is readable, page-jump ends use primary ink, and challenge settings take their title's colour, else the slug's (A98).
- **Work Detail's queue list** now removes a work when you uncheck a queue, as on the iPhone. It used to only add.
- **See all bookmarks** on your dashboard opens the author page on Bookmarks, as on the iPhone.
- **Lists that load from AO3** show placeholder rows instead of a spinner (U3).
- **Accent-coloured text** is readable in Dark and OLED (your Q19, both apps).
- **Words per hour** counts what each sitting read (Q27, both apps).
- **Your own Works and Series pages and the card details** are as on the iPhone (Q24, Q25), with your own-works totals kept.
- **Comments** says "AO3 couldn't be reached" or "You're offline" above a kept copy (both apps). Formatting tiles apply without closing the tray.

**Data and safety (both apps where marked):**
- **File Merge** keeps what a backup itself deleted (both apps). Deleted comments keep their replies.
- **Fixes from A65, A66, A67, A68 and A75:** backup and pairing, the first place after opening, fonts and hashes, a vanished book file, the converter's record and rebuild.
- **Fewer refused AO3 reads:** challenge settings ask only the form the collection's kind names (both apps).
- **Library's Add to Queue with a series** reads the series once, not twice.
- **The recovery copy** of a long text shares as a file instead of crashing on Android (A85).

**iOS:**
- Largest-text layouts no longer cover or cut content (U2, T-425, T-434).
- An AO3 collection names its maintainers again (T-426).
- A failed save says so (T-436).
- The parent URL wraps and keeps paste/undo, Read Aloud reads at the largest text, Comments shares the offline-error list, and the editor keeps writing room (T-440 to T-445, above).
- Plus T-419 to T-445 (TASKS.md).

**Screens with no mockup:** `REDESIGNED-WITHOUT-MOCKUP.md`.
- Each entry says what the screen was, what it is now, and what was kept.

**Not landed, on purpose:** "Discard changes?" when leaving an edited work form (your Q32). It was built, and kept on `android/agent-codex2-3gk` (`57036df6`).

## 3. What only you can do

**On devices** (the emulator and simulator are offline, have no speakers, and never sign in). `OWNER-DEVICE-CHECKS.md` lists each step.
1. **Read Aloud on a phone:** listen to a chapter, both voices, and the pronunciation page. It has never been heard on Android.
2. **The real AO3 site:**
   - Signing in.
   - Every write: comment, kudos, bookmark, subscribe, a work or chapter save, a collection, the challenge and moderation screens. Every write has only ever run against saved pages.
   - Questions 13, 14, 16 and 17 depend on this.
3. **Two real phones syncing through a cloud folder** (iPhone and Android). Which storage app lets both pick a folder is question 5.
4. **The Mac check:** after the Mac has read further in a work, does the iPhone open at the Mac's place or its own (A12-1)?

**Approvals:** merging to `main` (nothing is merged; `main` is unchanged since 2026-08-11), and anything about release or signing (untouched).

**Two separate asks from 10-23, still parked:**
- One click on the iPhone Duo's pose button in Device Hub, so Duo1 can finish checking the open display. The simulator runs on its cover; Duo2's Apple-guidance research is done and checked (`67f02ddf`). Parity is done, so Duo is next.
- May the five idle simulators be deleted (about 27 GB: Kudos iOS 27, Lanes C, D, F and Kudos Debug)? They are kept until you answer.

**Open questions** (`OWNER-DECISIONS-ANDROID.md`). Each has a default already in place, so none of them blocks work.

| # | Question | Until you answer |
|---|---|---|
| 1 | "+" on a light queue colour: white on iOS, black on Android | they differ |
| 2 | Default red accent on dark chrome (tab bar, toolbar glyphs) | unchanged |
| 3 | Toolbar and tab-bar colour on Home and Library (later owner instruction, 10-11) | follow the screen's wash (iOS T-399, Android `c268ba1a`) |
| 4 | Keep iOS's folder-sync safety changes (T-357)? | kept (recommended) |
| 5 | Which cloud storage for a shared folder? (needs you to try one) | folders sync as files; the cloud is unproven |
| 6 | Two devices syncing in the same minute | accepted: nothing is lost |
| 7 | iPhone↔Android deletions: pairing text; removing a paired device's deleted link, highlight or membership | unchanged on both |
| 8 | Android stricter in three places (later deletion, future dates, 128 MB vs 1 GB backups) | Android stricter |
| 9 | Android's Backup page extras (technical notes, pairing section) | kept |
| 10 | Library front page: an emptied section says "you haven't saved any" when a filter hides them | left as is (both) |
| 12 | Reader controls as glass; Search as the fifth tab; tab bar stays when a list scrolls | as they are |
| 13 | Moderation: confirm before Submit; one request per item; reload after a refusal | Android asks; one per item; they differ |
| 14 | Collection form: header-image alt text (sent by neither); the form after Create | shown on both; stays open |
| 15 | Maintainers' "Invite as" does nothing on either app | shown, no effect |
| 16 | iOS Challenge Settings reads every assignment page | iOS unchanged; Android reads none |
| 17 | iOS's work save leaves out some fields AO3's page sends | iOS unchanged; Android sends everything back |
| 18 | Backup with a deletion marker of an unknown kind | Android stops (recommended: skip it, as iOS) |
| 21 | A deletion doesn't reach a copy the other device made itself; Replace and later deletions | unchanged (recommended: A, and Replace retires contradicted records) |
| 22 | iPhone section headers capped at 2× at the largest text | capped |
| 23 | Blur mode: may lists, searches and filters name a blurred work? | yes (recommended: C) |
| 26 | A work form's short fields after a background kill | not kept (as designed) |
| 28 | A work card's date: 07/09/2026 on iOS, 09 Jul 2026 elsewhere | each as is (recommended: AO3's form) |
| 31 | A script in an imported EPUB can open a link without a tap (Android) | left |
| 32 | Ask "Discard changes?" when leaving an edited form | leave without asking |
| 33 | A device revoked on one Android phone stays trusted on your other phones | revoke on each phone |
| 34 | **New 10-23.** A new queue or collection with a name you already use: Android quietly uses the one you have and drops what you chose; the iPhone makes a second one | Android reuses (A); with A or C it should at least say so |

Answered during the sprint: 19, 24, 25, 27, 29 and 30 (on 10-20). 11 was answered on 10-04 and 20 is withdrawn. The iOS polish loop keeps its own short list in `~/kudos-ios-integrate/.claude-overnight/polish/OWNER-DECISIONS.md`.

## 4. Where everything is

**Branches.** None is merged to `main`; `origin/main` is `c878800e`, 2026-08-11.

**Team:** Claude-CLI is orchestrating until Claude-Code's limit resets, 2026-10-24 22:00, then hands back. Gemini is out on both accounts; Grok is out of balance. Sonnet is also out on both accounts from 10-24 07:40 (back about 10-29), so its work goes to Codex. The owner's overnight direction is parity only, in rounds: judge, one batch of fixes, one gate, re-shoot only the touched screens, judge again. Parity is done; the next focus is the iPhone Duo.

| Branch | Where | State |
|---|---|---|
| Android `android/redesign-parity` | `~/kudos-android-lane`, app in `android/` | pushed through `432c34f8` (A100), the last app commit |
| iOS `claude/polish-loop` | `~/kudos-ios-polish` | pushed, `d3e66077` (T-445), including T-440 to T-444 |
| iOS `integrate/cloud-redesign` | `~/kudos-ios-integrate` | pushed, `211d2076`, through T-445 |

The iPhone has integrate `e989fd84`, installed 10-14. It is installed again only when you ask.

**Docs (Android, `docs/android-port/` in the lane):**
- `OWNER-DECISIONS-ANDROID.md`: the questions.
- `DECISIONS.md`: what Claude decided, dated, with how to reverse each.
- `OWNER-DEVICE-CHECKS.md`: the device checks only you can do, step by step.
- `REDESIGNED-WITHOUT-MOCKUP.md`: screens with no artboard.
- `audits/` and `briefs/`: audits and follow-ups through A100 and round 3; I20 (the iPhone's filter sheet) is in `briefs/`. The CLI session's own notes are also in `~/kudos-agent-ios/docs/android-port/briefs/`.
- `briefs/`: each piece of work and its result, including Duo2's checked research and D7/D8's decision notes.
- `LIVING-PROMPT.md`: the loop's plan and day-by-day log. It is a local file, not committed.

**Docs (iOS):**
- `TASKS.md` in `~/kudos-ios-polish`.
- The polish loop's own `STATUS.md`, `OWNER-SUMMARY.md` and `INVENTORY.md` in `~/kudos-ios-integrate/.claude-overnight/polish/`.

**Screenshots:** `~/kudos-tools/pairs/tiles*/<screen>.png`. In each, the iPhone row sits above the Android row, in Dark, Light, Sepia, OLED and the largest text.
