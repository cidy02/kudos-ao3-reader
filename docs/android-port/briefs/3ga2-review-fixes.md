# Brief 3ga-2: fix the review's findings on 3ga before it lands

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Append a section "Review fixes" to your result file and write each item there as you finish it: what changed (`path:line`) and the test that fails without the fix. Hard rules as in your first brief (data and networking invariants, iOS is the source of truth at `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, nothing lost, ICU regex). The review findings, with quotes and each verifier's reasoning, are in `docs/android-port/audits/review-3fz-3ft-3fx-3ga.json` in the lane (`/Users/cidy02/kudos-android-lane`): read the entries for your patch. This worktree still holds your 3ga changes (not landed).

1. **`*/*` can read a huge file into memory.** Every picked file is read whole before its format is
   checked and kept until a dialog closes. Check the format from the first bytes (and the size)
   before reading the rest, and refuse what cannot be imported without loading it.
2. **Formats iOS names, Android mishandles.** With `*/*`, .rtf imports as a work full of control
   words and .docx/.odt get the archive message. Give each the specific refusal iOS gives
   (`Services/ImportedDocumentConverter.swift`, `ImportedFileFormat`), or convert where iOS
   converts.
3. **A picked .kudosbackup imports a backup's EPUBs as works.** Route a .kudosbackup (by its
   manifest, not only its extension) to the backup import sheet, as iOS does from Import.
4. **Login with no flash error on the login page.** iOS hands off to the visible AO3 page
   (`fallbackRequired`) for a CAPTCHA or interstitial; Android shows "Login failed". Match iOS.
5. **Queue Storage's byline is too large.** Use a compact, caption-sized byline that still opens
   the author (iOS's size), not work detail's 15.5sp accent byline.
