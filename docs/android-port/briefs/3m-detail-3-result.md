# 3m-detail-3 result

## Added

- Added the pushed-screen overflow button and mature-content menu. It is present only while the
  persisted `hideMatureContent` privacy setting is enabled, matching iOS. Its action uses the
  shared session-only `PrivacyGate`: Works and Bookmarks rows rated Mature or Explicit are omitted
  until the reader chooses to reveal mature works, and are hidden again when the reader toggles
  the action back. People is unaffected. The collection screen does not change the persisted
  privacy setting.
- Wrapped the page in the existing `KudosRefreshBox`. Pulling to refresh refetches the collection
  header and the selected Works, Bookmarks, or People page; the refresh indicator remains active
  until both requests finish.

## New user-visible strings

- `More actions` (overflow-button accessibility name)
- `Show mature`
- `Hide mature`

These match the labels used by iOS's `MatureRevealToggle`. The collection menu intentionally does
not add Expand All because the iOS collection page offers only the mature-content action.

## Signature change

`AO3CollectionDetailScreen` now takes `SettingsRepository` and `PrivacyGate`. `AppNavHost` passes
`container.settingsRepository` and `container.privacyGate`; all existing callbacks are unchanged.

## Left out

Android has no event or observable state equivalent to iOS's `.ao3CollectionDeleted`
notification. Its collection-management destinations use the existing web fallback, so a native
delete action cannot notify this screen while it is open. A later request may return `NotFound`,
but treating any fetch failure as a deletion signal would be incorrect. Automatic dismissal was
therefore left out rather than inventing a signal.

No Gradle build or test was run in this sandbox, as required by the brief.

## Review changes (Claude, before landing)

- **Mature rows are not omitted.** iOS's page never filters or blurs these rows: `workRows` in
  `AO3CollectionDetailView.swift` draws every row with `EnrichingAO3WorkRow`, and iOS's
  `PrivacyGate` only takes a `SavedWork` (the reader's own library). The menu action still flips
  the shared session gate, as iOS's `MatureRevealToggle` does; on both platforms it changes nothing
  on this page's AO3 rows. See DECISIONS.md.
- **Pull to refresh keeps the header.** iOS's `.refreshable` drops the segment from `loaded` and
  calls `loadIfNeeded()`, which fetches the collection header only while `show == nil`. The
  `refreshHeader` parameter is gone, which also saves one AO3 request per pull.
- The menu item carries the eye icon, as iOS's label and Android's other mature menus do.
- The `LazyColumn` body is indented to match its new nesting.

Checked on the emulator (Dark, demo signed in, `nav:ao3-collection-detail/yuletide`): the ⋮ glass
circle, the menu reading "Show mature" then "Hide mature" after a tap, and the refresh indicator
during a pull with the header and rows back afterwards.
