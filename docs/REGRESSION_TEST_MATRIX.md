# REGRESSION_TEST_MATRIX.md

What must keep working, where it's tested, and what is manual-only. Run everything via `Scripts/verify.sh` (or just the suite via `Scripts/test.sh 'platform=iOS Simulator,name=iPhone 17,OS=26.5'`; parallel testing deliberately disabled). 216 tests / 29 suites green as of T-74.

| Area | Invariant | Automated coverage | Manual-only residue |
|---|---|---|---|
| Privacy — blur | M/E works blur in Blur mode on List rows AND carousel cards (Home, Library incl. macOS branch, Subscriptions via `CanonicalWorkCoverCard`); tap-to-reveal via `PrivacyGate` | None (SwiftUI rendering) — logic lives in `SensitiveWorkRow`/`SensitiveWorkCoverCard` | Simulator pass per surface; Hide mode removes cards entirely |
| Privacy — button | `MatureRevealToggle` appears iff the **visible filtered** set contains M/E (`PrivacyGate.hasVisibleMatureWorks`); all surfaces incl. Library select mode | None | Filter Library to zero M/E → button disappears |
| Cards/select — Home/Library/Browse | Select mode toggles selection not navigation; selection survives carousel↔list switch; canonical dedup: one card per AO3 work | `CanonicalWorkMergeTests` (8: ID/URL matching, remoteLed/remoteOnly, ordering, duplicate mentions) | Tap-through of select flows |
| Multi-select batch actions | Browse bulk Save / Save-for-Later / Add-to-Collection / Add-to-Queue resolve sequentially, report partial failures, never open sheets with empty work lists, cancel on view exit | None directly; primitives covered by `ReadingQueueTests`, `PreservedWorkTests` (revive-on-reacquire) | Offline batch → error alert; leave screen mid-batch |
| Search/index | Case+diacritic-insensitive, AND-across-terms; reindex on import/refresh/restore; launch rebuild once; index never in backups | `WorkSearchIndexTests` (6) | — |
| Library filters | Facet semantics unchanged; empty facets build no per-work Sets | `SearchFiltersTests` (AO3 side); Library side untested *(gap)* | Filter panel spot-check |
| AO3 parsing | Search pages, subscriptions, bookmarks, tags, metadata parse; failures degrade without data loss | `AO3ClientTests`, `AO3SubscriptionsParseTests`, `WorkTagsTests`, `FandomCatalogCacheTests` | Live-HTML drift (parsers are fixture-tested) |
| Networking politeness | Pace/coordinator/coalescer behavior; retry only transient; Retry-After honored | `AO3RequestCoordinatorTests`, `RequestCoalescerTests`; retry/backoff logic untested directly *(gap — pace()/withRetry are private)* | 429 behavior against live AO3 (don't provoke it) |
| Deletion/recovery | Soft delete → 90-day recovery; restore retracts tombstones; sweep gated; revive-on-reacquire (all paths); TOCTOU merge in `importEPUB` | `PreservedWorkTests` (13+) | Recently Deleted UI tap-through |
| Backup round-trip | v7 export/import; tombstone suppression + newer-snapshot revival; flags `incomingWins`-gated; progress fields travel; index excluded; EPUBs restored | `KudosBackupTests`, `PersistenceSyncTests`, index exclusion in `WorkSearchIndexTests` | Cross-device restore on real hardware |
| Folder sync | Two-device convergence; conflict folding; dirty-flag; gate reentrancy; failed write preserves package; skip-unchanged + re-restore on change | `FolderSyncTests` (incl. the two T-73 tests), `FolderSyncBackgroundTaskTests` (shouldSchedule) | Real iCloud Drive propagation, quota/offline UX, BGTask firing (Xcode "Simulate Background App Refresh") |
| Reinstall/update survival | EPUBs in App Support (device backup); Keychain session survives; folder bookmark dies but package survives → re-pick folder restores; index/migration self-heal via version stamps | `PersistenceSyncTests` (migration stages) | Actual reinstall walkthrough |
| EPUB import + enrichment | `importUserEPUB` dedup/restore outcomes; `importEPUB` merge-not-duplicate; metadata/tags seeded from EPUB then enriched from AO3; imports searchable immediately | `EPUBTests` (incl. sample.epub round-trip), `PreservedWorkTests`, `WorkSearchIndexTests` | Settings → Import EPUB picker actually presenting (see T-73 note) |
| Reader progress | iOS: saved on every `locationDidChange`; survives force-quit; drives Continue Reading | `SavedWorkProgressTests`, `ReadiumReaderTests` | Kill-app-mid-chapter check; macOS legacy reader *(least covered area)* |
| Queues | Membership lifecycle, preservation, series preservation accounting, removal semantics | `ReadingQueueTests` (largest suite) | — |
| Write actions | Kudos/comment POST construction, CSRF, no-retry | `AO3WriteActionsTests` (construction only) | ⚠️ Never live-verified — release gate item |

## Known coverage gaps (acknowledged, not licenses to skip)

1. ~~`LibraryFilters.matches` has no dedicated unit suite~~ — closed by `LibraryFiltersTests` (T-74).
2. ~~Retry/pacing policies untested~~ — closed by `AO3ClientPolicyTests` over the now-internal `AO3Client.retryDelay` and pure `paceStep` (T-74). `withRetry`'s loop itself remains review-enforced.
3. SwiftUI presentation behavior (file importers, pickers, blur rendering) — logic-tested only; the TASKS.md UI approval gate covers it.

Mechanical invariants (single UA, one fileImporter, no `isDeleted` model property, index-out-of-backups, no raw AO3 URLSessions, staged package writes, no `try!`/`as!`) are enforced by `Scripts/check-invariants.sh`, which runs as step 1 of `Scripts/verify.sh`.

**When you add behavior in an area above, add the test to the named suite** — new suites need `@Suite(.serialized)` + registration in the schema helper only if they touch SwiftData/the gate.
