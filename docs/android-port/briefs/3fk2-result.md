# 3fk-2 result

Dispatch: `c682c744edba10b8729723adf280ab7e7d37405f`, branch
`android/agent-codex-3fk2`, worktree `/Users/cidy02/kudos-agent-codex`.
The branch already existed at that exact commit with a clean tree. No branch
switch, commit, push, sign-in, or AO3 request occurred. Changes are uncommitted
for Claude, as brief 3fk requires. `TASKS.md`, Room entities/schema, backup format,
stored cookie/session format, document converters, and 3fj fixes are untouched.
SameSite is deliberately unchanged per the owner's decision; Claude owns its
`DECISIONS.md` entry.

Items 4–7 are implemented. Item 8's existing reader date/status fields are fixed;
gift-recipient reader UI is absent and was left outside this conditional item.
Each implementation followed inspection of the dispatch code and the named iOS
tests under `/Users/cidy02/kudos-ios-polish` (read-only).

## 4. Logout clears scoped WebView cookies

Confirmed: `auth/AndroidAO3CookieStore.clear` enumerated only cookies visible at
the root URL, then expired default-path copies. It could not discover cookies
scoped to `/users`, `/works`, or another AO3 host.

It now awaits `CookieManager.removeAllCookies` on the main dispatcher, then
flushes. The clear is non-cancellable so the auth repository's session mutex
cannot release while an outstanding removal could erase a later login's cookies.
The callback is awaited even when no cookies were present.

Tradeoff: Android's public CookieManager API cannot enumerate stored domains and
paths. Complete removal therefore clears **all cookies in this app's shared
WebView store**, including any non-AO3 cookies. It does not clear another app's
browser cookies or the user's library.

`AO3CookieBridgeAllowListTest.logoutClearsPersistedAndWebSessions` ports the iOS
logout state, notice, durable deletion, username and removal-marker assertions
through the actual Android bridge. It seeds secure HttpOnly path- and
subdomain-scoped cookies and checks their absence after logout. Robolectric
coverage does not replace a real Chromium WebView scope/ordering check.

## 5. Hostile EPUB preflight

Confirmed: `works/EpubMetadataReader.isReadablePackage` used ZipFile's central
directory but read only the container and package document, accepting hostile
unreferenced entries.

Before reading either document, it now validates every central-directory entry:

- Nonempty safe names, with iOS's backslash, NUL, absolute-path, `..`, empty
  component and drive-prefix rules; trailing directory slashes remain allowed.
- Unique entry names, including duplicates of package documents.
- At most **10,000 entries**, **200,000,000 expanded bytes per entry**, and
  **500,000,000 expanded bytes total**, matching `MiniZip.Limits.epub`.
- Stored/DEFLATE methods, matching sizes for stored entries, no nonempty output
  with zero compressed size, and iOS's integer-division **1,100:1** ratio ceiling.

The aggregate uses Long arithmetic and each term is capped before addition.
Android reads EPUB ZIPs without extracting them to disk: these are preflight
and ZIP-bomb protections, not an extraction-folder containment fix. This change
hardens the existing `isReadablePackage` gate used by `BackupMergeService`; it
does not add new validation gates to local imports/downloads or change converters.

`HostileEpubPreflightTest` ports the named MiniZip hostile assertions through a
readable minimal EPUB with unreferenced hostile additions. Tiny raw ZIP fixtures
carry declared bomb sizes without allocating/decompressing those sizes. Tests
also cover duplicates, a valid directory marker, valid minimal EPUBs, and the
exact entry-count, per-entry-size, aggregate-size and ratio boundaries.

## 6. Blank account usernames return null

Confirmed: `network/ao3/account/AO3AccountUrls.userScopedUrl` appended the trimmed
empty username as an empty path segment.

`url`/`userScopedUrl` now return null for blank usernames. Collection-work URLs
remain independent of the username. `AccountListRepository.load` and the account
URL users in `AO3WriteRepository.unsubscribe`, `deleteReading`, and
`clearReadingHistory` handle null before any page request or write preparation.
The separate named-subscription and collections builders are unchanged.

`AO3AccountUrlsTest.buildsMarkedForLaterURL`, `buildsHistoryURL` and
`buildsBookmarksURL` port the iOS normal URL, pagination and empty/whitespace
username assertions, with tab/newline blanks included.

## 7. Availability preserves the last copy and reports attempts

Confirmed: `WorkMetadataRefresh.refresh` ignored all failures including 404 and
never persisted the recovered work ID. `WorkRepository.refreshMetadata`'s
parallel tag-only path stamped only `lastUpdateCheck` for a 404.
`WorkAvailabilitySweep.sweep` incremented checked only for success/404; its
pending filter also excluded previously unavailable works permanently.

Both single-work refresh paths now use the existing `WorkIdentityIndex`, retain a
recovered representable AO3 ID before fetching, mark a 404 unavailable with a
check timestamp, and clear the flag on recovery. Existing EPUB bytes, progress,
flags and download date survive. Nondefinitive failures preserve availability
and its timestamps. Existing stored IDs work even without a source URL.

The sweep keeps serial spacing, seven-day cooldown and run cap. It counts each
completed inconclusive attempt in `checked`, assigns neither availability
outcome, retains recovered IDs, and can recheck unavailable works after their
cooldown. A confirmed recovery clears their flag. Availability-only changes bump
the modification clock when the unavailable flag changes.

`WorkAvailabilityTest` ports WorkAvailabilityTests' 404/checked/recovery,
inconclusive/old-flag, non-AO3 and recovered-ID assertions through Room and the
full refresh. It additionally checks the tag-only refresh and byte-for-byte
survival of the local EPUB. `WorkAvailabilitySweepTest` gains the inconclusive
summary assertion, 404/recovery outcomes, non-AO3/Recently Deleted exclusion and
cancellation-with-partial-results assertions. Existing tests already cover
ordering, cooldown, cap and spacing. Android's last-copy protection assertion is
`ao3Unavailable && hasEpub && isProtected`; visual badge review remains manual.

## 8. Existing reader metadata fields

Confirmed: `WorkDetailContent` renders completion status and
`WorkDetailFactsCard` renders Published and the updated date. However,
`AO3WorkMetadata`/its parser omitted those fields, the work-page-to-summary
conversion dropped them, and detail state ignored persisted local dates.

The transient work metadata now carries published/updated date strings and a
nullable completion status. The parser reads `dd.published`, `dd.status` (with
`dd.updated` fallback), and the **preceding unclassed label**. As iOS, Completed
wins as true, Updated wins as false, otherwise the chapter ratio determines
status or leaves it unknown. `WorkMetadataMerger` and full metadata refresh
populate the **existing** SavedWork fields without erasing them for blank data.
`toRemoteSummary` carries the values to work detail; detail state uses saved
local dates with remote fallback. The iOS fixture's work summary also gets the
existing work-level selector fallback when there is no preface wrapper.

`WorkPageMetadataParityTest` ports the applicable reader-field assertions from
`parsesWorkPageMetadata` and `parsesWorkInProgressStatusFromUnclassedLabel`, plus
ratio/unknown fallbacks. `WorkDetailMetadataBridgeTest` checks the actual
work-page-to-detail conversion. `WorkMetadataMergerTest` and
`WorkAvailabilityTest` check saving/refresh persistence and blank-data retention.
This does not add work-page series parsing, outside the requested fields.

**Gift recipients: conditional skip.** `AO3SearchParser.parseWorkSummary` and
`AO3WorkSummary` have no gift-recipient field, and work-list/detail components
have no gift-recipient badge or line. Android's gift controls are the writing
editor's form fields (`WritingWorkFormScreen`/`WritingAssociationPickers`), a
different parser and feature; the author Gifts tab also does not display blurb
recipients. Thus `parsesGiftRecipientsFromTheBlurbHeading` has no existing reader
surface to repair. No recipient model/UI or schema was added.

## Verification and next step

Passed here:

- `android/Scripts/check-invariants.sh` (exit 0).
- `git diff --check` (exit 0).
- Direct compilation with cached Kotlin 2.3.21 and JUnit 4.13.2, using actual
  production sources and cached dependencies: `HostileEpubPreflightTest`,
  **8 tests passed**, compile/test exit 0.
- The same direct compiler/JUnit method for `WorkPageMetadataParityTest`,
  **3 tests passed**, compile/test exit 0.

No Gradle invocation or dependency download was attempted, per the brief.
Compiler outputs were confined to temporary directories and deleted; no stub
files or helper scripts remain. The direct runs do **not** verify the full app,
Room, WebView dispatcher behavior, Compose, or the added integration tests.

Claude next: run `android/Scripts/verify.sh` outside this sandbox, including
`AO3CookieBridgeAllowListTest`, `AO3AccountUrlsTest`, `WorkAvailabilityTest`,
`WorkAvailabilitySweepTest`, `WorkMetadataMergerTest`,
`WorkDetailMetadataBridgeTest`, `IncomingEpubGateTest`, and the two directly
verified classes. Check scoped-cookie logout on a real WebView and inspect work
detail dates/status for a local copy and an ID-only remote destination; retain
the project's human screenshot gate. Review and commit the explicit changes on
this branch. No iOS port is needed; this follows the referenced iOS behavior.
