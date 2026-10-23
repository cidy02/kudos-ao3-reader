# Brief I11 (iOS): a failed save says so, instead of closing as if it worked

Worktree `/Users/cidy02/kudos-agent-ios`, branch `claude/agent-ios-i11` (from `claude/polish-loop`'s tip,
which now has your I9, I9b and I10 as T-434). Same rules as before: compile iOS (arm64 simulator)
and macOS with your own derivedDataPath; no tests, no simulator (Claude runs them), no commits, no
sign-in, no AO3; SwiftLint at HEAD's level. Write `docs/android-port/briefs/I11-result.md` with
`path:line` per item, and message me when done.

Source: Codex's code comparison A84a (`/Users/cidy02/kudos-android-lane/docs/android-port/audits/A84a-result.md`,
lines 6, 9, 16, 18, 56 and their evidence at 82, 93, 160, 169, 324). On five sheets the iPhone
saves best-effort and closes, so a failed write looks like a saved one; Android keeps the sheet
open and says "Could not save" (`library/QueueEditorSheet.kt`, `library/CollectionEditorSheet.kt`,
`settings/PronunciationSettings.kt` in `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/`).
1. New Reading Queue and Edit Queue (`Features/Library/NewReadingQueueSheet.swift:143`, `:376-380`;
   `Services/ReadingQueueService.swift:194`, `:236`).
2. New Collection and a collection's details (`Features/Library/NewCollectionSheet.swift:159-161`;
   `Features/Library/Collections.swift:194-205`, `:225-228`, `:248`, `:265`, `:293`).
3. The pronunciation editor (`Features/ReaderReadium/ReaderPronunciationSettingsView.swift:217-225`,
   `:407-409`).

For each: first read how the write can fail (a `try?` that drops the error, a save that throws, a
store write). If it can't fail in practice, say so and change nothing. Otherwise keep the sheet open
on failure and show the failure in the sheet with Android's words where they fit ("Could not
save. Try again."); success behaves exactly as today. Use the app's existing error presentation
(`UserFacingError`, an inline footnote or the app's alert pattern; look at how other sheets show a
write failure) rather than a new one. Where the service decides, let it report the failure to its
caller instead of swallowing it, and keep every other caller's behaviour.

Tests: for each service whose signature changes, a unit test that a failed write reaches the
caller (a failing store or context, as the suite's existing persistence tests fake one). Name the
suite each goes in; Claude runs them.
