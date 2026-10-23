# Review A89 (read-only): Codex's Android batch 3gx against the iPhone

You are reviewing, not editing: **change no file except your result note; no builds, no Gradle,
no git commands that change anything, no sign-in, no AO3.** Write
`/Users/cidy02/kudos-agent-ios/docs/android-port/briefs/A89-result.md` (create it first).

**What:** Codex's 3gx delivery, uncommitted in `/Users/cidy02/kudos-agent-codex` (branch
`android/agent-codex-3gx`, base `8ffb409d`; `git -C /Users/cidy02/kudos-agent-codex diff` shows it, about
72 files). Its brief: `docs/android-port/briefs/3gx-a82b-android.md` and `3gx-continue.md` there; its own
account: `docs/android-port/briefs/3gx-result.md` there (items, owner questions, iOS side, tests).
The iPhone reference is `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/` at `claude/polish-loop`.
Note the Android lane has moved on since 3gx's base (`47fbc6ec`: KudosPaginationBar, FilterTagPicker,
ReaderContentsSheet, CustomizeThemeSheet, PronunciationSettings, CollectionEditorSheet); flag any
3gx hunk in those files that would undo those changes.

Look for, with `file:line` on both sides, a severity (P1 data loss or crash, P2 wrong behaviour a
user meets, P3 minor) and a concrete failing case:
1. **Lost behaviour or information:** anything Android did before 3gx that it no longer does and
   that `docs/android-port/DECISIONS.md` (in the lane, `/Users/cidy02/kudos-android-lane/docs/android-port/`)
   says Android keeps, or that iOS also does. The owner's rule: parity, with no lost features or
   information.
2. **Wrong parity:** a change that claims to match iOS but does not (read the iOS file it cites).
3. **Persistence and AO3 traffic:** any change to Room, backups, sync, or what is fetched from AO3
   (count requests; a new or repeated read is a finding). `ReadingQueueRepository`, `WorkRepository`,
   `AO3BrowseRepository`, `SettingsRepository` and `AnnotationRepository` are in the diff.
4. **Tests:** for each new or changed test, would it fail with its change reverted? Name any that
   would still pass.
5. **The `GIT_BRANCH` BuildConfig field** in `android/app/build.gradle.kts`: does anything leak into a
   release build that should not (a branch name in About is fine if iOS shows one; check).

Also give your verdict on each of 3gx's eleven owner questions: a real owner decision, or one the
code or DECISIONS.md already settles (say where).

End with one line: P1 / P2 / P3 / unconfirmed counts. Message me when done.
