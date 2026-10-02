# Brief 2d Result: Four Parity Fixes from Tasklist Audit

Implemented the four small parity items from `docs/android-port/TASKLIST-AUDIT.md`:

1. **E1 (Shake-to-report direction reversal)**:
   - Ported direction reversal detection from iOS `ShakeDetector.swift` into `support/ShakeDetector.kt`.
   - Added `samplesReversed`, `dominantAxis`, `countReversals`, `countRecentReversals`, and `pruneAndCountReversals` to `ShakeMath` requiring `REQUIRED_REVERSALS = 2` within a `REVERSAL_WINDOW_MS = 600L` (0.6 s) window above a 2 m/s² floor, retaining the 13.5 m/s² threshold and 1.5 s debounce.
   - Evaluates `Sensor.TYPE_LINEAR_ACCELERATION` for direction reversals while retaining raw accelerometer magnitude evaluation.
   - Added unit test suite in `app/src/test/.../support/ShakeDetectorTest.kt`.

2. **A5 (Scrub-origin tick on reader slider)**:
   - In `reader/ReaderScreen.kt` (`ReaderBottomProgress`), captured `scrubOrigin` from `Slider`'s `DragInteraction.Start` and reset on `Stop`/`Cancel`.
   - Draws a vertical origin tick (2.dp × 14.dp, `RoundedCornerShape(1.dp)`) matching iOS `ReaderPositionCard.swift` with no magnetic snap.

3. **D2 (AO3 unavailable works list)**:
   - Added `settings/AvailabilitySweepScreen.kt` listing library works where `ao3Unavailable == true` and `!isDeleted`, matching iOS copy (`"No longer on AO3 (N)"`).
   - Tapping an unavailable work invokes `onOpenWork(id)` opening it via `WorkDetailSource.LocalWork`, matching the Library.
   - Registered `Routes.AvailabilitySweep` ("availability_sweep") in `Routes.kt` and `AppNavHost.kt`.
   - Added "Unavailable Works" link in `settings/SettingsScreen.kt` beside existing sweep counts, leaving `WorkAvailabilitySweep.kt` untouched.

4. **B2 (Local tag suggestions on Search)**:
   - In `search/SearchScreen.kt`, collected `savedWorks` and `userTagNames` via `workRepository` and passed `collectLocalTagSuggestions(savedWorks, userTagNames)` to `SearchFilterSheet`, mirroring `browse/FandomWorksScreen.kt`.
