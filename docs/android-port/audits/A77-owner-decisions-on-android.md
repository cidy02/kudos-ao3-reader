# A77: is every iOS owner decision present on Android?

**Read only: change no code, commit nothing, sign in nowhere, contact no website, run no Gradle.**
Write `docs/android-port/audits/A77-result.md` FIRST and fill it in as you go.

Part of the port's definition of done: "Every iOS behaviour decided by the owner is present on
Android." The owner's decisions are recorded in three places:

1. The list "Owner decisions Android must reproduce" (below, copied from the port's working notes):
   T-335 Edit Queue replaces Rename (the New Queue sheet in edit mode); T-336 custom colours stored
   exactly as picked (`colorHex`, plus `hue`); T-338 press-and-hold menus on queues (Edit,
   Pin/Unpin, Delete); T-340 Home queue cards are a stacked deck; T-343 the queue page has no
   bottom switcher bar; T-350 the New Collection wash follows the picked colour; T-337 one control
   per action, the top chrome wins (filters in the top-right filter button, create actions a top
   "+"); T-339 Select lives in the "…" menu; T-348 theme-coloured controls use the exact accent;
   reads AO3 will refuse are not made (the prompt meme's close date asked once per opening and only
   for a collection's owner); T-342 the explanatory text rewritten for a non-technical reader
   (iOS strings verbatim); T-341 the "Keep works you read" setting; T-344 "Downloaded" means kept
   and Read never says download; T-345 the download ring replaces the reading ring while
   downloading and the card greys out; T-346 Remove Download un-keeps only; T-347 Recently Deleted
   has sections, with finished, un-kept copies held for 60 days.
2. iOS code comments that cite the owner: run
   `grep -rn "owner, 2026-\|Owner, 2026-\|(owner 2026-\|owner decision" /Users/cidy02/kudos-ios-polish/kudos-ao3-reader`
   (46 lines, 30 files). Each is a rule the owner chose.
3. `docs/android-port/OWNER-DECISIONS-ANDROID.md` (answered questions) and the owner entries in
   `docs/android-port/DECISIONS.md` (search "owner").

For **every** decision in 1 and 2 (and every answered question in 3 that names a behaviour), say
against this worktree's Android code (HEAD `a5a2c7f4`, `android/app/src/main/java/...`):

- **present**: Android does the same. Android `path:line` and iOS `path:line`.
- **different**: say what each app does, both `path:line`, and what a reader would see.
- **absent**: no Android code for it; say what is missing.
- **not applicable**: an iOS-only platform matter, or an Android decision in `DECISIONS.md` that
  replaces it (quote its date and title).

Open the code; do not decide from names or comments alone. A verdict without a `path:line` on
both sides does not count. End with the list of **different** and **absent** items, ranked by
what a reader would notice, and the counts.
