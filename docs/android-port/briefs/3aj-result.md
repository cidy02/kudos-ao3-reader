# Brief 3aj result

**Landing note (Claude, 2026-10-05).** Landed as written. Gate green (1,410 tests). Seen on the
emulator: the Subscriptions page with two works under "New since you last looked" and Mark All
as Seen clearing them; the pairing section's "Demo reading tablet" row with Rename and Revoke,
and the Revoke dialog (cancelled, not confirmed); and the reader's Find in Work on "The Long
Way Down" grouping "lantern" as "This Chapter (Ch. 1)", Preface, Chapters 2 to 7 and Afterword
in order, and answering a one-letter search. On an emulator that had visited Subscriptions
before, the badges read 5 and 8 new, not 2 and 3: its stored "last seen" counts were zero, and
the fixture rightly leaves stored counts alone. A fresh install shows 2 and 3 (covered by the
test, not seen).

Implemented on `android/agent-gemini-3aj`, uncommitted. No branch changes, commits,
pushes, sign-ins, AO3 requests, Gradle or Xcode runs. `TASKS.md`, iOS, Room schemas
and backup formats are unchanged. No binaries, stub files or helper scripts added.

All launch instructions below assume a debug build with `--ez kudosDemoLibrary true`.
Subscriptions additionally use the existing `--ez kudosDemoSignedIn true` **local
fixture session**; no login UI, credentials or real sign-in is involved. The existing
demo interceptor answers matching AO3 requests locally and refuses unmatched ones.

## Reader

Reach: Library → Reading Queues → Neon reread → **The Long Way Down** → Contents → Chapter 7 → reader menu → Find in Work.

`DemoLibrary.buildSearchEpub` generates a Preface, seven story chapters, and an
Afterword, each with its own XHTML spine item, EPUB 3 navigation entry and NCX entry.
It reuses `EpubBuilder.buildEpub` for XHTML, stylesheet, container and package
metadata, then assembles them in memory. The shared builder's multi-chapter overload
currently flattens everything into one spine item; that production builder is unchanged.

The Long Way Down already has `7/18` chapters in the read-only iOS demo, so seven
story chapters fit its existing metadata. Its metadata and stored progress are
unchanged. All other demo EPUBs, including screenshot default **Sodium Lights**,
retain their existing single-spine content. Relaunching an existing seeded demo
regenerates only The Long Way Down's downloaded fixture, so reinstall is unnecessary.

- Search `lantern`: one occurrence in each of the nine sections; inspect grouping
  and the pinned “This Chapter (Ch. 7)” group.
- Search `compass`: appears only in Chapters 2 and 6, which are not adjacent.
- Search `a` while in Chapter 7: Chapter 3 contains 240 short original paragraphs,
  each with three standalone `a` words (case insensitive), exceeding 200 matches
  before the current chapter; inspect automatic paging toward Chapter 7.
- Also open Preface/Afterword and repeat `lantern` to inspect their honest labels.

All new prose is original fixture filler written for this brief.

Regression test: `DemoLibraryTest.searchFixtureHasSeparateChaptersAndOriginalSearchTermsEvenOnAnExistingDemo`
checks the generated spine, navigation/NCX destinations, section classification,
search terms, high match count, Sodium Lights' single spine and old-demo upgrade.

## Subscriptions

Reach: local fixture session → Account → Subscriptions (`nav:account-list/Subscriptions`) → wait for enrichment → More actions → Mark All as Seen.

The bundled `ao3_subscriptions.html` retains the iOS reference's work names, IDs
and author links for its first two works, plus its existing series/user entries.
It adds Paper Cranes, using the iOS demo's title, author `origamist`, fandom
`Haikyuu!!`, General rating, `1/1` chapters and 2,210 words. Its synthetic fixture
work ID is `999000002`. The iOS subscription fixture has no chapter counts, so the
first two works' posted/seen counts below are new demo values.

| Work | Metadata request | Fixture | Posted / last seen | New |
| --- | --- | --- | --- | --- |
| A Study in Pink | `/works/45678901?view_adult=true` | `ao3_demo_subscription_pink.html` | 5 / 3 | 2 |
| Another Fic | `/works/12345?view_adult=true` | `ao3_demo_subscription_another.html` | 8 / 5 | 3 |
| Paper Cranes | `/works/999000002?view_adult=true` | `ao3_demo_subscription_cranes.html` | 1 / 1 | 0 |

The index stays sparse: the existing `AO3SparseWorkEnricher` looks up those addresses
through the demo interceptor. Exact work routes precede the general work fixture;
edit, navigate and comment paths retain their earlier mappings. The index request
`/users/AO3_Reader/subscriptions?type=works` (and paginated variants) still maps to
`ao3_subscriptions.html`.

`DemoLibrary.seedPreferences` seeds missing entries through the real
`SubscriptionWatermarks.save` store before writing the library. Existing entries
are preserved, so Mark All as Seen clears the new counts and they stay cleared on
demo relaunch. To repeat the initial badge/action screenshots after marking seen,
use a fresh demo app-data install.

Regression tests: `DemoNetworkBlockTest.subscriptionPageAndItsMetadataLookupsAreAnsweredByBundledDemoFixtures`
checks the bundled index, all three real metadata URL shapes, returned counts and
action-route precedence with a fail-fast interceptor preventing any network fallback;
`DemoLibraryTest.subscriptionFixturesHaveTwoUnreadWorksAndOneSeenWorkAndKeepMarkAllSeen`
checks `2/3/0` new counts and that Mark All as Seen survives reseeding.

## Pairing

Reach: Account → Settings → Backup (`nav:backup`) → Deletion signing → **Demo reading tablet** → Revoke.

`DemoLibrary.seedPreferences` calls the real `TombstoneTrustStore.trust` with a
locally generated Ed25519 public key, label **Demo reading tablet**, and trust date
**2026-07-01 12:00 UTC**. The date is outside the 24-hour Undo Trust window, so the
existing row offers Revoke. There was no paired device in the iOS reference to copy.
The row currently displays the name and public-key prefix; the date is stored as
real pairing metadata, not added to the production UI.

Each fresh demo install generates a new peer key with Tink's existing
`Ed25519Sign.KeyPair.newKeyPair`; its private bytes are cleared and no private key
is persisted or embedded. It is never the emulator's own signing key, an imported
key, or a real remote device. Nothing can sign a deletion as this fixture peer.

Revoke follows the existing `KeyRevocationService`: both reasons remove the trusted
key and row; **Stolen or compromised** also denylists the public key, while
**Retired or sold** does not. No works were deleted by this peer, so automatic
restoration restores zero works. A demo-only preferences marker prevents creating
another peer after either revoke reason on relaunch. A fresh demo app-data install
recreates the fixture with a different public key.

Regression test: `DemoLibraryTest.pairedDemoDeviceIsDisposableAndRevokeSurvivesReseedingForBothReasons`
checks the real store's label/date, valid non-own public key, repeated-seed identity,
both revoke reasons, denylist behavior, zero restoration and no reseeding afterward.

## Validation and handoff

Passed here: `git diff --check`; a read-only Python static check of the bundled
subscription IDs, chapter counts and exact demo routes. Reviewed real signatures
for the EPUB builder, file store, section builder, metadata parser, watermark store,
Tink key generation, trust store and revocation service. `MainActivity` changes only
pass application context to its two existing debug-demo seed calls; no production
screen, repository or network path receives a new demo branch.

**Not run:** Kotlin compilation, JUnit/Robolectric, Readium opening/search and emulator
screenshots. Claude should run from `android/`:

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest \
  --tests 'io.github.cidy02.kudos.app.DemoLibraryTest' \
  --tests 'io.github.cidy02.kudos.network.ao3.DemoNetworkBlockTest'
```

Those runs must establish compilation and the fixture/test claims above. Then run
the broader Android suite and manually verify EPUB opening, chapter grouping,
pinning and paging for the search terms; `+2` and `+3` subscription badges and Mark
All as Seen disappearing after use; and the pairing row/dialog/removal/relaunch
behavior. No visual correctness or successful Readium integration is claimed here.
