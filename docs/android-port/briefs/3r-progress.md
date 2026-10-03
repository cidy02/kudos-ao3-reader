# Brief 3r: opening a work must never lose its reading position

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. No network
except Gradle's offline cache. Leave changes uncommitted. Build and test, and iterate until green:
`cd android && JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=$HOME/Library/Android/sdk ./gradlew :app:assembleDebug :app:testDebugUnitTest --offline --console=plain -q`
Use **emulator-5554 only** (Claude verifies on emulator-5556).

## The bug (you found it during 3c-fix)
With the demo library, "Sodium Lights" shows 42% everywhere. Opening it in the reader rewrote its
progress to 0%. The demo seeds `legacyReaderProgress = 0.42`, `lastSpineIndex = 1`, and no
`readiumLocator`. Owner rule: behaviour must be identical across platforms, and losing someone's
place is a data-loss bug.

## Find out what iOS does
- `kudos-ao3-reader/Features/ReaderReadium/`: how the reader picks its starting position for a work
  that has `legacyReaderProgress` and/or `lastSpineIndex` but no `readiumLocator` (search
  `legacyReaderProgress`, `initialLocation`, `locator(fromProgress`, `lastSpineIndex`).
- When iOS writes progress back: only after the reader has actually moved, or immediately on open?
  Search `markProgressModified`, `readiumLocator =`, and `lastScrollFraction`.
- `kudos-ao3-reader/Models/Models.swift`: how the displayed fraction is computed (`readingProgress`
  or similar), and which field wins when several are set.

## Do
1. Make Android open at the same place iOS does for every combination: locator; legacy fraction
   only; spine index only; nothing.
2. Make Android write progress only when iOS does. Opening and closing without reading must
   leave the stored fraction unchanged.
3. Make the displayed fraction (rings, "42%") come from the same rule as iOS's.
4. Write unit tests for each combination above, including "open then close without moving keeps
   42%", using the reader repository's injected clock.
5. Write `docs/android-port/briefs/3r-result.md` (under 300 words): the iOS rule (file:line), what
   Android did before, and the fix.

Don't touch `app/MainScaffold.kt`, the `library/Library*` files, `backup/` or migrations.
