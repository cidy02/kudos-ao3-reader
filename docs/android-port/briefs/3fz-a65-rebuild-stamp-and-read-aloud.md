# Brief 3fz: the converter stamp and Read Aloud's three gaps (A65 #61, #116, #85, #88; Android)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3fz-result.md` **first**, then write each item's entry the moment it is
done (an earlier agent on this plan read for an hour and wrote nothing): **done / not real / left**,
`path:line`, the iOS rule (`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only), tests.

Hard rules: `docs/DATA_AND_PERSISTENCE_INVARIANTS.md`; no Room schema change expected; backup
manifest v8, additive keys only; iOS is the source of truth; nothing Android has may be lost;
Android's ICU regex rejects some JVM-accepted flags (`RegexPortabilityTest`).

1. **#61, the converter stamp.** iOS writes `Originals/<work-uuid>.conversion.json` beside a
   converted import's preserved original (`Services/WorkConversionRecord.swift`:
   `converterVersion`, `format`, `originalFileName`, `convertedAt`; `isStale` when below
   `ImportedDocumentConverter.converterVersion`), finds stale works (`Services/WorkReconversion.swift`;
   a missing record counts as version 0) and in My copy rebuilds a stale work at once with its
   explanation, asking "Rebuild this work?" only when it is current
   (`Features/WorkDetail/WorkProvenanceSections.swift:120`–`:150`). Android always asks
   (`works/WorkDetailScreen.kt:1045`). Port: Android's own converter version constant (start at 1;
   say where to bump it), the same sidecar file and JSON shape written on every conversion and
   rebuild, the stale rule, My copy's two paths with iOS's words. Check whether either app's
   backup or sync carries the sidecar (and the originals); carry it the same way iOS does, and
   note that a version number is per app (an iOS record read on Android is compared with Android's
   own scale: say what that means and choose the conservative reading). If iOS's reader shows a
   "Rebuild from Original" pill for stale works, add it (LIVING-PROMPT lead, P3).
2. **#116, hold-seek.** Holding Previous/Next while Read Aloud is paused steps through positions
   on iOS (`Features/ReaderReadium/ReaderSpeechSkip.swift:10`, `seekIndex`); Android's controller
   (`reader/speech/ReaderSpeechController.kt:162`) has a paragraph queue and no hold. Port the
   gesture and the stepping rule onto Android's queue.
3. **#85, a long work starts slowly.** Android reads the whole work's prose before the first word
   (`reader/ReaderContentText.kt:16`); iOS starts from the current chapter
   (`Features/ReaderReadium/ReadiumReaderView.swift:1750`). Start speaking from the current
   resource and read the rest as speech goes on, keeping "to the end" (3ed) and the author's-notes
   switch (3ee) working.
4. **#88, voice availability.** `AutomaticTTSService` checks the offline voice only at start
   (`reader/speech/AutomaticTTSService.kt:69`); iOS checks before each utterance
   (`Services/TTS/AutomaticTTSService.swift:45`). Match iOS.

Tests for each (JVM rules: the stale rule and sidecar round trip, the seek stepping, the first
utterance coming from the current resource without reading the others first).
