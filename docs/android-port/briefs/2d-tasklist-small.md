# Brief 2d: four small parity fixes from the tasklist audit

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. You cannot run
Gradle: write code that compiles by careful reading, and check that each symbol you use exists
with that signature. Claude builds and sends errors back.

Source of truth: `docs/android-port/TASKLIST-AUDIT.md`, which has exact file:line evidence for
each item. Re-read the current code at those spots first, since line numbers may have shifted
slightly. For each item, read the iOS file it names and match its behaviour. The old branch
commits it cites (`git show 3c0c1cc7 -- <path>`) are reference only: never paste a hunk without
checking it against today's code.

1. **E1, shake-to-report needs a direction reversal.** In `support/ShakeDetector.kt`, port iOS
   `kudos-ao3-reader/Support/ShakeDetector.swift`: `requiredReversals = 2` within a 0.6 s window,
   counted from sign changes of the dominant axis. Keep the existing 13.5 m/s² threshold and the
   1.5 s debounce. Factor the reversal counting into a pure function and test it in
   `app/src/test/.../support/ShakeDetectorTest.kt`.
2. **A5, a scrub-origin tick on the reader's bottom progress slider.** In `reader/ReaderScreen.kt`,
   `ReaderBottomProgress` (~line 908): while the user drags, draw a small tick at the position the
   drag started, as iOS `ReaderPositionCard.swift` does (lines 12 and 30). Only the tick: no snapping.
3. **D2, a list of works AO3 marked unavailable.** Add a screen reachable from Settings beside the
   existing availability-sweep counts (`settings/SettingsScreen.kt` ~691-712). It lists works
   with `ao3Unavailable == true`, and tapping one opens it like the Library does. Mirror iOS
   `AvailabilitySweepView.swift` (lines 20, 33-35, 61-79), including its copy. **Do not change**
   `works/WorkAvailabilitySweep.kt`: its manual-only design is a deliberate later decision
   (`bb165940`).
4. **B2, local tag suggestions on Search.** In `search/SearchScreen.kt` (~281-283), pass the
   same local tag pool `browse/FandomWorksScreen.kt` (~89-96) builds with
   `collectLocalTagSuggestions`, instead of the empty list.

Don't touch `backup/`, `ui/subject`, `ui/theme`, `data/local` or migrations.
When done, write `docs/android-port/briefs/2d-result.md` (under 300 words).
