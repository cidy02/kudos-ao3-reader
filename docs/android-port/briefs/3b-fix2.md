# Brief 3b-fix2: two small Library details

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. You cannot run
Gradle: write code that compiles by careful reading. Claude builds and checks it on the emulator.
Compare against `docs/android-port/shots/ios/library-dark.png` (iOS, freshly seeded).

1. **Toolbar circle size.** Library's top-right +/filter/... circles (`library/LibraryShellChrome.kt`,
   drawn by `app/MainScaffold.kt`) are smaller than Home's. Home's circles are the iOS size: 44dp glass
   circles with 17sp glyphs, the "+" in the accent (see how `home/HomeShellChrome.kt` and
   `MainScaffold.kt` draw Home's). Make Library's identical to Home's, by sharing the same code path,
   not by copying values.
2. **Fandom kicker names.** iOS shows "STAR WARS" where Android shows "STAR WARS - ALL MEDIA T…". iOS
   peels AO3 fandom tag names for display: `kudos-ao3-reader/` → search for `FandomDisplayName` (e.g.
   `bareTitle(_:among:)`, and the kicker's use of it on cover cards). Port that peeling logic to Kotlin
   as a pure function with a unit test covering the iOS cases (read the iOS tests: `grep -rn
   FandomDisplayName KudosTests`). Use it wherever cover cards and ledger rows show a fandom kicker
   (`ui/subject/SubjectWorkCoverCard.kt`, `home/HomeFacts.kt` `primaryFandom`, queue chrome). Keep
   Home's current output wherever it already matches iOS.

Don't touch `backup/`, `data/local`, migrations, or `library/ReadingQueue*` / `library/Queue*` (another
agent is working there). Write `docs/android-port/briefs/3b-fix2-result.md` (under 200 words).
