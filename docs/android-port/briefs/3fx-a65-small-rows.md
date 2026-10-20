# Brief 3fx: A65's small rows (Android)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Leave a result
file `docs/android-port/briefs/3fx-result.md`, written as you go: per row, **confirmed / already
fixed / not real** with `path:line`, what changed, the iOS code it follows
(`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`, read-only), the test added.

Hard rules: iOS is the source of truth; `docs/AO3_NETWORKING_POLICY.md` is binding; no Room or
backup change; nothing Android shows today may be lost. Android's ICU regex rejects some
JVM-accepted flags (`RegexPortabilityTest`).

Rows from `docs/android-port/audits/A65-result.md` §1 (**confirm each first**):

1. **#99** Search's filter badge counts the subject fandom and the sort direction, so it
   disagrees with the hero's Filters count (`search/SearchFilterHelpers.kt:131`; iOS
   `Features/Search/SearchResultsHero.swift:320`). Count as iOS counts.
2. **#100** A long press on the pager's ‹ / › goes to the first / last page on iOS
   (`Features/Search/SearchPaginationBar.swift:29`); Android has no long press
   (`ui/components/KudosPaginationBar.kt:82`). Add it; keep Android's First/Last buttons only if
   iOS has them too, else follow iOS (say which).
3. **#101** A tapped tag's works address leaves out `view_adult=true` and `utf8`/`commit`
   (`network/ao3/search/AO3SearchUrlBuilder.kt:32`; iOS `Services/AO3Client.swift:1189`). Build
   it as iOS does, parameter for parameter.
4. **#102** A ticked challenge-settings checkbox sends both AO3's hidden `0` and the checked `1`
   (`network/ao3/account/AO3ChallengeSettingsForm.kt:122`; iOS `Services/AO3ChallengeModels.swift:410`).
   Send what iOS sends.
5. **#124** Add Chapter's custom-date switch has no spoken name; iOS says "Custom publication
   date" (`writing/WritingChapterFormScreen.kt:138`; iOS `Features/Writing/AddChapterView.swift:265`).
6. **#113** `RegexPortabilityTest` (`app/src/test/.../network/ao3/RegexPortabilityTest.kt:13`)
   scans only `network/ao3`: widen it to all of `src/main/java`, and fix anything it then finds.
7. **#108** Add the two missing tests 3fn named: Clear History when the session changes during
   its GET (nothing is posted), and a 307/308 answer to a write (not re-sent)
   (`network/ao3/writes/`; iOS `KudosTests/AO3WriteDispatchFenceTests.swift:291`).
