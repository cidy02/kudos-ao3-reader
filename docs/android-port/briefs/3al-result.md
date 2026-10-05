# Brief 3al result

**Landing note (Claude, 2026-10-05).** Landed with two changes. The demo's Bookmarks page had
been replaced by a page holding only Ashfall; it now keeps its two older bookmarks, their four
pages and their Rec, Private and Favorite marks, with Ashfall added in front, and the two tests
that expected a single bookmark look for Ashfall among three. Ashfall's stored address is the
plain work address, without the "view_adult" query that belongs to a request. Gate green (1,421
tests). Seen on the emulator: the series page with its works in order, the collection's
Bookmarks and People tabs, and Ashfall blurred with "Tap to reveal" at the head of Bookmarks.
**Section 4 is a finding, not a fixture:** Android's Series and Authors tabs on Subscriptions
are empty placeholders that ask AO3 for nothing and say "No series subscriptions", where iOS
lists them. That is brief 3am.

Implemented, uncommitted on `android/agent-gemini-3al`. This handoff follows
[`3aj-result.md`](3aj-result.md). No commits, pushes, branch switches, sign-ins,
AO3 requests, Gradle or Xcode runs. `TASKS.md`, iOS, Room and backup formats stay
unchanged. All new prose is original demo filler.

Launch a debug build with `--ez kudosDemoLibrary true`. Account destinations also
need `--ez kudosDemoSignedIn true`, the existing local fixture session, without
using login or credentials. The active demo interceptor answers locally and
refuses unmatched AO3 URLs.

## 1. Series with works

Reach: Library → Reading Queues → Neon reread → **Sodium Lights** → its **My Series** row in the work details.

`/series/999` (optional trailing slash and query parameters) →
`ao3_demo_series.html`, using the iOS subscriptions fixture's **My Series** name
and ID. One page, four works in this order:

| Part | Work | Synthetic work ID | Rating | Chapters | Words | Access/status |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Sodium Lights | 999000005 | Teen And Up Audiences | 1/1 | 62,004 | Complete |
| 2 | Ashfall | 999000003 | Mature | 9/? | 41,780 | In progress |
| 3 | Paper Cranes | 999000002 (retained from 3aj) | General Audiences | 1/1 | 2,210 | Restricted, complete |
| 4 | The Long Way Down | 999000004 | Mature | 7/18 | 84,120 | In progress |

Titles, authors, fandoms, ratings, categories, chapters and words mirror the
read-only iOS `App/DemoLibrary.swift`. Series membership and the restriction are
new demo values; iOS has no `/series/999` detail fixture. The description and work
summaries are original. Aggregate stats: four works, **190,114 words**, incomplete,
seven bookmarks; dates July 1–8, 2026. All except the word sum are invented where
iOS has no value. The demo marks Paper Cranes restricted in its series blurb;
this is a listing fixture, not a change to authorization or the earlier 3aj metadata.

`DemoLibrary.withDemoListLinks` sets Sodium Lights' existing series fields. It
remains a local import with an empty work source URL. No work metadata request is
needed to open its series. `/series/999/edit` keeps `ao3_series_edit.html`.

`SeriesWorksScreen` calls `AO3SeriesRepository.seriesPage`, which parses only work
blurbs with `AO3SearchParser`. The screen derives its title from the first work's
series link. The fixture can carry a description and aggregate stats, but the
current Android screen has no place to display those series-level fields.
Pagination is one page, so there is no second-page request.

Missing-fixture test: `DemoNetworkBlockTest.demoSeriesPageHasFourOrderedWorksAndKeepsEditRouting`
requires a local 200 response, all four parsed IDs/positions, complete/in-progress
flags, the restricted marker, description and aggregate stats. The seed link and
older-demo upgrade are also checked by
`DemoLibraryTest.demoListLinksUpgradeExistingRowsAndKeepReadingState`.

## 2. Collection bookmarks and people

Reach: local fixture session → Account → Collections → **Winter Exchange 2026** → Bookmarks / People.

The existing collection is **Winter Exchange 2026** (`winter_exchange`), from the
iOS `ao3_collection_show.html`. `AO3CollectionDetailRepository` makes these GETs;
Bookmarks and People are tabs, loaded on demand:

| Address | Fixture | Contents |
| --- | --- | --- |
| `/collections/winter_exchange/profile` | `ao3_collection_show.html` (existing) | Profile, 234 works / 18 bookmarks, maintainers AO3_Reader and comod |
| `/collections/winter_exchange/works?page=1` | `ao3_tag_works.html` (existing) | Existing work list |
| `/collections/winter_exchange/bookmarks?page=1` | `ao3_demo_collection_bookmarks.html` | 18 original bookmarked works, IDs 999001001–999001018, with summaries/stats |
| `/collections/winter_exchange/people?page=1` | `ao3_demo_collection_people.html` | AO3_Reader, comod, saltandsilver, meridian, tidewrack |

The new routes allow an optional trailing slash and ignore query parameters as
the existing demo router does. Both new lists have one page. Bookmark count 18
matches the reference profile; work titles, IDs, demo_keeper bylines, notes and
prose in the new bookmarks fixture are original filler.

People names come from iOS's profile/participants fixtures. Roles are AO3_Reader
and saltandsilver (Owner), meridian (Moderator), tidewrack (Member), plus comod
(Maintainer, as named in the profile). Their work counts 2/1/3/1/0 in displayed
order are new demo values; iOS has no public People fixture/counts.
`/collections/winter_exchange/participants` still answers with the existing
`ao3_collection_participants.html`; no management form was changed.

People parsing returns identities and work counts. The People screen does not
display membership roles; the fixture can label maintainers/members in HTML but
cannot make role badges appear without a production UI change.

Missing-fixture test: `DemoNetworkBlockTest.winterCollectionTabsAreAnsweredWithBookmarksAndPeople`
requires local 200s for all four addresses, 18 parsed bookmark IDs, all five parsed
people/counts, both profile maintainers, roles in HTML, and preserved participant
route precedence. Either new fixture disappearing fails this test.

## 3. Mature library work on an account list

Reach: local fixture session, Privacy → Hide mature content on and Blur selected, no reveal active → Account → Bookmarks → **Ashfall** (tap to reveal).

**Ashfall**, Mature, TempusFugit, 41,780 words, `9/?` chapters (iOS demo
values), gets synthetic AO3 identity `999000003` in the demo seed and the local
fixture session's Bookmarks page. The real `CanonicalWorkMerge.remoteLed` pairs
by source URL/ID; `visibleEntries` keeps that local pairing in Blur mode and
`PairedWorkRow` uses the library's existing privacy predicate.

| Address | Fixture | Purpose |
| --- | --- | --- |
| `/users/AO3_Reader/bookmarks` | `ao3_demo_account_bookmarks.html` | One full bookmark blurb for Ashfall (bookmark 503), matching the library source URL |
| `/works/999000003?view_adult=true` | `ao3_demo_ashfall.html` | Matching metadata for optional enrichment/refresh |

The account URL is produced by `AO3AccountUrls`; it adds `?page=N` only after page
one. This fixture has one page. The exact account route precedes the general
author-bookmarks route, so other demo author profiles retain their old fixture.
The work metadata route precedes the generic work response and follows edit,
navigate and comment routes; those earlier action fixtures retain precedence.

`DemoLibrary.withDemoListLinks` supplies both `sourceUrl` and `ao3WorkID` using
existing model fields. The identity is synthetic because iOS's Ashfall has no AO3
ID. Reading progress 0.63, saved/offline copy, known count 7, queue and collection
memberships remain as seeded before. Already-installed 3aj demos gain the two
missing links by updating the existing records, preserving their UUIDs and state;
nonblank source/series URLs are left alone. Repeated seeding adds no rows.

Privacy is not forced or reset by this brief. Fresh defaults already enable Blur
(`PrivacySettings`); an existing install may need Settings → Privacy adjusted.
Restarting the process clears a session reveal. Reveal-all or a prior Ashfall
reveal makes the row visible normally.

Missing-fixture test: `DemoLibraryTest.demoBookmarkPairsWithTheMatureLibraryWorkAndBlursUntilRevealed`
opens the route-selected bundled bookmark asset, parses the account page, matches
its ID to the seeded library through `CanonicalWorkMerge`, and checks the
Obscured → Visible predicate on reveal. It verifies the real copy/progress/known
count remain intact. `DemoNetworkBlockTest.demoAccountBookmarksAndAshfallMetadataHaveTheSameIdentity`
also requires local 200s and matching rating/count/fandom/category metadata, and
checks action/other-author route precedence. Actual blur rendering remains manual.

## 4. Series and Authors subscriptions: no supported new-item display

*Superseded on 2026-10-05 by brief 3am (`3am-result.md`): the two tabs now list what AO3
returns.*

Android's `SubscriptionsBrowser` in `AccountWorksListScreen.kt` renders an
unconditional empty state for both Series and Authors. Switching those pills
does not issue a request. `AccountListRepository`/`AO3AccountUrls` load only
`/users/AO3_Reader/subscriptions?type=works`; `AO3AccountParser.parseSubscriptionsPage`
keeps only `/works/` links. Its watermark store counts work chapters only.

The iOS reference's `AO3NamedSubscriptionsList.swift` does fetch `type=series`
and `type=users` pages and displays name/byline, pagination, navigation and
unsubscribe. Neither named tab has a new-item badge or last-seen watermark.
The existing bundled index already contains **My Series** (`/series/999`, by
seriesauthor) and **someuser** (`/users/someuser`), exactly as iOS does. Preserve
these entries; add no fabricated unread fields, new routes or production UI.

Reach: local fixture session → Account → Subscriptions → Series / Authors; both
currently show their empty states, even though the bundled HTML has named entries.

Address/fixture: the page's sole index request is
`/users/AO3_Reader/subscriptions?type=works` (later pages add `&page=N`) → existing
`ao3_subscriptions.html`, followed by 3aj's three work-metadata requests and
fixtures documented in [`3aj-result.md`](3aj-result.md). The Series/Authors pills
make **no additional request**, so there is no missing named-tab fixture to add.

Missing-index-fixture test:
`DemoNetworkBlockTest.subscriptionIndexRetainsIosSeriesAndAuthorLinksWithoutTreatingThemAsWorks`
requires the locally served index to retain My Series/seriesauthor and someuser,
while the Android parser still produces only the three works. This protects the
existing named entries and fails if the index asset disappears; it does not claim
those entries or unread counts appear in Android's named tabs.

## Validation and handoff

Added five debug HTML fixtures; changed only `DemoLibrary.kt`, `DemoNetwork.kt`,
their existing test classes and this report. No screen/repository/parser code,
preferences, schema, manifest format or production network behavior changed.
`MainActivity` still invokes the seed only for the debug demo request. The active
interceptor still refuses missing/unmatched AO3 URLs locally. All added network
tests put a fail-fast interceptor after the demo block, preventing network fallback.

Passed here: `git diff --check`; a read-only standard-library Python check of all
five new assets' structure, decoded route patterns/precedence, ordered series
IDs/positions/counts/restriction, word sum, 18 unique collection bookmark IDs,
people names/counts and matching Ashfall identity/rating/chapters/words. Reviewed
the real seed call sites, model fields/mappers, repository signatures, URL builders,
parsers, identity matcher, derived search indexing and privacy predicate. The
Python check did not execute Kotlin or Jsoup.
**Not run:** Kotlin compilation, JUnit/Robolectric or emulator screenshots.
Claude should run from `android/`:

```sh
./gradlew :app:assembleDebug :app:testDebugUnitTest \
  --tests 'io.github.cidy02.kudos.app.DemoLibraryTest' \
  --tests 'io.github.cidy02.kudos.network.ao3.DemoNetworkBlockTest'
```

Those runs must establish compilation and the test claims above, especially the
Room-backed old-demo upgrade, canonical pairing and asset loading. Then run the
broader Android suite. On both a fresh install and an existing 3aj demo, manually
verify the Sodium Lights series link, four works in order, Paper Cranes' lock
marker, complete/WIP cards, collection bookmarks/people and pagination, and
Ashfall's paired library row blurring/revealing in Bookmarks. Check Series/Authors
still show the documented empty states and that Works' 3aj badges/Mark All as Seen
still work. No visual correctness is claimed here.
