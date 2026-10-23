# Kudos Android: owner summary

*Draft, 2026-10-22 evening, for the owner back from the sprint that began 2026-10-20 12:30.*

**In one paragraph:** Android now matches the iPhone on every screen the two apps had been compared on, in all four themes and at the largest text. The last full comparison matched 65 of 67 screens, and the two small differences have been fixed since. The remaining 70 screens that had never been put side by side are being compared now (A82). Tests are green (3,308) and lint has no new warnings. Data parity holds in tests both ways but has never been tried on two real phones. What is left is mostly yours: hearing Read Aloud on a phone, the real AO3 site (we never sign in), two phones syncing through a cloud folder, one Mac check, merges to `main`, and 25 open questions, each with a safe default already in place. Nothing has been merged to `main`.

## 1. Where it stands, against "Done"

"Done" (Living Prompt §0) has five Android items, plus the iOS list (§5c) and the bug hunt (§5d).

1. **Every screen verified against the iPhone in Dark, Light, Sepia, OLED and the largest text: not yet; most of the way.**
   - **Compared:** all 70 screens that had a pair. Each was shot on both phones in five columns, differences were fixed, and the screens were shot again (A69 to A76). A76 matched 65 of 67; its two minors were fixed (`8667ab4d`). A79 rechecked the 15 screens changed since and all match. A80 added four new pairs (search filters, library filters, sign-in, a comment thread) and its faults are fixed (`0ddb694f`, `cde116dd`).
   - **Not yet:** A81 found 76 iOS screens never put side by side. 70 of them are A82 (below). The other 6 are not comparable for now: three have no Android screen by decision, two are recorded gaps, and the in-app web browser needs AO3.
   - **Also not yet:** the §7 matrix's marks have not been updated since 10-11. And the passes compared the two phones with each other, not with the artboards.

   > **A82 (placeholder):** 70 screens being compared now (`audits/A82-shots.md`; both apps open each one with a `shot:<name>` debug route). Result: ___ match, ___ minor, ___ differ. Fixed: ___.

2. **Every owner decision in §6 present on Android: done.** A77 checked 72: 62 were present and 10 were gaps. Eight were fixed (3go, `8c80b3b7`), one is not a fault (Android uses buttons where iOS uses swipes, decided), and one is your question 9.

3. **Data parity (model, backup, sync, round trip both ways): done in tests, never tried on two real phones.**
   - Each app restores the other's backups and reads the other's sync folder in tests. The shared fixtures now carry fonts, pronunciations and deletion dates both ways (Android `4a63e64b`, iOS T-423). That work found an iOS restore fault, which is fixed.
   - A75 re-checked 195 iOS data rules against Android: 152 were already there. The real gaps are fixed (3gq, `35c986f0`), and two are decisions or your question 33.
   - The sync questions 4–8, 18, 21 and 33 are yours.

4. **Build and tests green, no new lint warnings: done at the last landing.** 3,308 tests green (`23135534`). Lint shows 0 new warnings against the lane's start; four old ones are gone (`cde116dd`).

   > **A84 (placeholder):** Grok's code comparison of the two apps. Result: ___.

5. **An owner summary and `OWNER-DECISIONS-ANDROID.md`: this file (draft) and that file.** It holds 33 questions: 7 answered, 1 withdrawn, 25 open (listed in §3 below).

**iOS (§5c): done, except one Mac check.** These landed today:
- Comments says why it shows a kept copy (T-430).
- The editor's Preview and recovery copy no longer stall at AO3's 510,000-character limit: 0.72 s → 0.02 s (T-431).
- The prompt meme's settings read asks only the form that matches the collection's kind (T-429).
- The largest-text fixes you approved (T-425).

Left: on a Mac, after the Mac has read further, does the iPhone open at the Mac's place (§3)?

**Bug hunt (§5d): done.** Every audit has been run and triaged, with no open P1 or P2. The last open line is the same Mac check.
- A helper's review of today's commits (A83) found one P2 and five P3s, most of them in debug-only code.
- The P2: the recovery copy could not be copied whole. Fixes for it and the Android P3s are in the lane, uncommitted while this was drafted.

## 2. What changed during the sprint (2026-10-20 to now)

**You'll notice these on Android:**
- **Reader:**
  - Highlight marks the passage at once, and Add Note opens the full editor (your Q30).
  - Customize Theme is the iPhone's reading-text sheet (Q29), `c6b0576a`.
  - While you read, the system bars hide; they come back with the reader's controls. Predictive back is on (your approved U1, `6a14cec3`).
  - A regression from the new fonts code, which stopped any work from opening, was fixed the same day (`edc3eac7`).
- **Read Aloud:**
  - Pronunciation corrections, as on iOS (`c62201d0`); Android cannot play them yet because the voice pack ignores them, and the page says so.
  - Settings › Listening can download the Kokoro voice, and has Engine and Pitch (`fcba3075`).
  - Previous and Next move by chapter, and a mini-player stays when the controls hide (`2c5117d5`).
- **Every screen the comparison passes covered:** fixed to match, in all four themes and at the largest text (A69–A80: `e306895e`, `701595c9`, `be73a737`, `1bbefdfd`, `8667ab4d`, `cde116dd`). Examples:
  - Settings pages on the iPhone's card surface.
  - Library History and Favorites as compact rows.
  - Comments' replies and badges.
  - Nothing cut short with "…" at 2× text.
  - The Library filter sheet at full height.
- **Lists that load from AO3** show placeholder rows instead of a spinner (U3, `98586ab2`).
- **Accent-coloured text** is readable in Dark and OLED (your Q19, both apps).
- **Words per hour** counts what each sitting read (Q27, both apps), `c17d376d`.
- **Your own Works and Series pages and the card details** are as on the iPhone (Q24, Q25), with your own-works totals kept.
- **Comments** says "AO3 couldn't be reached" or "You're offline" above a kept copy (both apps).

**Data and safety (both apps where marked):**
- **File Merge** keeps what a backup itself deleted (both apps, `dfef0970`, iOS T-424). Deleted comments keep their replies.
- **Fixes from A65, A66, A67, A68 and A75:** backup and pairing (`e8258853`), the first place after opening, fonts and hashes (`35c986f0`), a vanished book file cleared on every work (`94501db8`), the converter's record and rebuild (`609e4c1b`).
- **Fewer refused AO3 reads:** challenge settings ask only the form the collection's kind names (`3e23e694`, iOS T-429).

**iOS:**
- Largest-text layouts no longer cover or cut content (U2, T-425).
- An AO3 collection names its maintainers again (T-426).
- Plus T-419 to T-424 and T-428 to T-432 (TASKS.md).

**Screens with no mockup:** `REDESIGNED-WITHOUT-MOCKUP.md`.
- 54 screens have no artboard: 21 are matched, 28 are being compared (A82), and 5 can't be compared yet.
- 45 were restyled on Android after the iPhone.
- Each entry says what the screen was, what it is now, and what was kept.

**Not landed, on purpose:** "Discard changes?" when leaving an edited work form (your Q32). It was built, and kept on `android/agent-codex2-3gk` (`57036df6`).

## 3. What only you can do

**On devices** (the emulator and simulator are offline, have no speakers, and never sign in):
1. **Read Aloud on a phone:** listen to a chapter, both voices, and the pronunciation page. It has never been heard on Android.
2. **The real AO3 site:**
   - Signing in.
   - Every write: comment, kudos, bookmark, subscribe, a work or chapter save, a collection, the challenge and moderation screens. Every write has only ever run against saved pages.
   - Questions 13, 14, 16 and 17 depend on this.
3. **Two real phones syncing through a cloud folder** (iPhone and Android). Which storage app lets both pick a folder is question 5.
4. **The Mac check:** after the Mac has read further in a work, does the iPhone open at the Mac's place or its own (A12-1)?

**Approvals:** merging to `main` (nothing is merged; `main` is unchanged since 2026-08-11), and anything about release or signing (untouched).

**Open questions** (`OWNER-DECISIONS-ANDROID.md`). Each has a default already in place, so none of them blocks work.

| # | Question | Until you answer |
|---|---|---|
| 1 | "+" on a light queue colour: white on iOS, black on Android | they differ |
| 2 | Default red accent on dark chrome (tab bar, toolbar glyphs) | unchanged |
| 3 | Should toolbar and tab bar take the hero's colour on Home and Library? | no, app accent |
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

Answered during the sprint: 19, 24, 25, 27, 29 and 30 (on 10-20). 11 was answered on 10-04 and 20 is withdrawn. The iOS polish loop keeps its own short list in `~/kudos-ios-integrate/.claude-overnight/polish/OWNER-DECISIONS.md`.

## 4. Where everything is

**Branches.** None is merged to `main`; `origin/main` is `c878800e`, 2026-08-11.

| Branch | Where | State |
|---|---|---|
| Android `android/redesign-parity` | `~/kudos-android-lane`, app in `android/` | pushed, `1380183c` |
| iOS `claude/polish-loop` | `~/kudos-ios-polish` | pushed, `7dc23568` |
| iOS `integrate/cloud-redesign` | | every polish commit cherry-picked. Local tip `1d968a58`; the last remote ref read was `eae467d3`, so the T-432 picks may still need a push |

The iPhone has integrate `e989fd84`, installed 10-14. It is installed again only when you ask.

**Docs (Android, `docs/android-port/` in the lane):**
- `OWNER-DECISIONS-ANDROID.md`: the questions.
- `DECISIONS.md`: what Claude decided, dated, with how to reverse each.
- `REDESIGNED-WITHOUT-MOCKUP.md`: screens with no artboard.
- `audits/`: A1–A83, each result with its triage.
- `briefs/`: each piece of work and its result.
- `LIVING-PROMPT.md`: the loop's plan and day-by-day log. It is a local file, not committed.

**Docs (iOS):**
- `TASKS.md` in `~/kudos-ios-polish`.
- The polish loop's own `STATUS.md`, `OWNER-SUMMARY.md` and `INVENTORY.md` in `~/kudos-ios-integrate/.claude-overnight/polish/`.

**Screenshots:** `~/kudos-tools/pairs/tiles*/<screen>.png`. In each, the iPhone row sits above the Android row, in Dark, Light, Sepia, OLED and the largest text.
