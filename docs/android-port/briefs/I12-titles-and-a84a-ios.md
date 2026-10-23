# Brief I12 (iOS): titles still cut, and A84a's last iPhone items

Worktree `/Users/cidy02/kudos-agent-ios`. Start a branch `claude/agent-ios-i12` from
`claude/polish-loop`'s tip **after Claude says I11 is committed there** (your I11 edits are applied in
polish as T-436; record your I11 worktree diff as a commit on `claude/agent-ios-i11` first, then switch).
Same rules: compile iOS (arm64 simulator) and macOS with your own derivedDataPath; no tests, no
simulator, no commits on polish, no sign-in, no AO3; SwiftLint at HEAD's level. Write
`docs/android-port/briefs/I12-result.md` with `path:line`, and message me.

1. **`wrappingInlineTitle` does not wrap in practice.** Fresh shots on the iOS 27 simulator
   (`/Users/cidy02/kudos-tools/pairs/shots/`): `i_revokedevice_dark.png` reads "Revoke Demo reading ta…"
   at the default size and `i_revokedevice_big.png` "Revoke Demo re…"; `i_addworks_big.png` "Add to
   Neon…". The principal item stays one line in the bar. `i_bookmarkform_big.png` and
   `i_availability_big.png` now fit (the size cap helps short titles). Find a way that shows the whole
   title, keeping all its information (the device's or queue's name must stay readable), at every
   size: for example a short title with the name in the content's header, or iOS 26's
   `navigationSubtitle`. Android shows "Revoke Demo reading tablet" as a wrapping dialog title. Say
   which you chose and why; Claude re-shoots to check.
2. **A84a's iPhone side that I11 did not cover** (Codex's list in
   `/Users/cidy02/kudos-android-lane/docs/android-port/briefs/3gx-result.md`, "iOS side"):
   - Pronunciation list, import (Paste) and delete storage errors are dropped
     (`Features/ReaderReadium/ReaderPronunciationSettingsView.swift:224` and the load/apply/delete
     paths); Android says "Could not delete correction. Try again." etc. Same treatment as I11.
   - Add Works counts selections that mature-content filtering hides again, while only eligible works
     are added (`Features/Library/AddLibraryWorksSheet.swift:114`): count what will be added.
   - The comments chapter picker keeps spinning when AO3 returns no chapters
     (`Features/Comments/CommentsView.swift:1072`): show the empty result as Android does.
   Skip "the series card reverse gap" (it would add AO3 reads; out of scope).
