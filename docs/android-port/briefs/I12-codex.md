# Brief I12 for Codex (iOS): titles still cut, and A84a's last iPhone items

**Write code in this worktree only (`/Users/cidy02/kudos-agent-ios`, branch `claude/agent-ios-i12`, from
`claude/polish-loop` 72c0d603). Do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run xcodebuild (Claude builds and tests). Do not edit `TASKS.md`.** Keep SwiftLint
at HEAD's level (`.swiftlint.yml`). Every iOS-only API inside `#if os(iOS)`: the app also builds for macOS.
Write `docs/android-port/briefs/I12-result.md` (replace the stub) with `path:line` per item, and for any
test you add, what it checks and what it does with its change reverted.

The task is the brief `docs/android-port/briefs/I12-titles-and-a84a-ios.md` in this worktree (ignore its
first paragraph's workflow lines; the rules above replace them). In short:
1. `wrappingInlineTitle(_:isActive:)` (`kudos-ao3-reader/UIComponents/SubjectScreen.swift:148`) puts a
   two-line `.headline` in the bar's principal slot, but the bar keeps it to one line: fresh simulator
   shots read "Revoke Demo reading ta…" at the default size (`Settings/PairingSheet.swift:242`) and
   "Add to Neon…" at the largest (`Features/Library/AddLibraryWorksSheet.swift:108`). Make the whole
   title readable at every size without losing information (the device's or queue's name must stay
   visible): for example a short title ("Revoke Device", "Add Works") with the name shown in the content
   or as `navigationSubtitle` (iOS 26+, guarded), or another approach you can justify from how the app's
   other sheets name their subject. Keep VoiceOver reading the full title once. Say what you chose.
2. A84a's iPhone side that the earlier batch (T-436) did not cover, per Codex's own 3gx "iOS side" list
   (`/Users/cidy02/kudos-android-lane/docs/android-port/briefs/3gx-result.md`):
   - `Features/ReaderReadium/ReaderPronunciationSettingsView.swift`: load, Paste Corrections (import) and
     delete drop storage errors (`try?`). Show them with the app's alert pattern, as T-436 does for the
     editor's save ("Could not delete correction. Try again." etc., Android's words in
     `/Users/cidy02/kudos-android-lane/android/app/src/main/java/io/github/cidy02/kudos/settings/PronunciationSettings.kt`).
   - `Features/Library/AddLibraryWorksSheet.swift:114`: the Add count includes selections that mature-content
     filtering hides again, though only eligible works are added. Count what will be added.
   - `Features/Comments/CommentsView.swift:1072`: the chapter picker keeps spinning when AO3 returns no
     chapters. Show the empty result (Android: `comments/CommentsScreen.kt`).
