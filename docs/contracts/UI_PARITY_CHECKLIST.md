# UI Parity Checklist

Status: Phase 12 Codex pass. Android should be native Material 3, but it must keep
the same product meaning, information hierarchy, and available actions as the
Apple app. No item below should be treated as final parity until a human manual
device audit has passed.

## Navigation

Status: Partial, needs human review.

- Complete: Android top-level destinations are Home, Library, Browse, and Account.
- Complete: Search is a global app-bar action, not a fifth peer tab.
- Complete: Work Detail is the canonical destination from Library, Home, Search,
  Browse, Account lists, and Reader work links where native hydration exists.
- Complete: Reader hides app chrome and uses focused reader controls.
- Complete: wider screens use a Material navigation rail; phones use bottom
  navigation.
- Needs human review: Android back behavior, focus order, and tablet/landscape
  ergonomics need device verification.

## Information Density

Status: Partial.

- Complete: AO3/search/browse/account work cards show title, author, fandom,
  rating/warnings/categories, summary, key tags, word count, chapters, kudos,
  comments, and hits when parsed.
- Complete: Library/Home saved-work cards show local state such as downloaded,
  favorite, finished, progress, rating, words, chapters, and fandoms where known.
- Partial: Android does not yet have Apple-style generated cover cards or
  carousel art; it uses dense Material cards.
- Needs human review: confirm the card hierarchy remains scannable at large font
  sizes and on narrow devices.

## Home

Status: Partial.

- Complete: Home is now a real offline dashboard backed by the Library snapshot.
- Complete: Continue Reading, Favorites, Recently Opened, and Recently Added
  shelves are present and privacy-aware.
- Complete: Home routes to canonical Work Detail and Reader.
- Deferred: Android Home does not yet show AO3 Subscriptions or Recently Updated
  shelves.
- Needs human review: visual density and empty-state tone on device.

## Library

Status: Partial.

- Complete: saved works, Continue Reading, Reading History, Recently Added,
  Favorites, local search, deterministic sorts, favorite/download/finished
  filters, user tag filters, collection filters, AO3 metadata facet filters, and
  mature-content filtering exist.
- Complete: Library remains offline-first and does not call AO3 to populate local
  shelves.
- Complete: free-text Library search excludes obscured mature-work metadata, so a
  sensitive title/tag does not reveal a masked card.
- Complete: reading progress display prefers chapter ratio for multi-chapter works
  before falling back to in-chapter scroll fraction, matching Apple parity.
- Deferred: AO3 update checking/Recently Updated, biometric reveal UI, full tag
  and collection management screens, bulk actions, and device visual verification.

## Browse

Status: Partial, needs human review.

- Complete: native Browse loads AO3 `/media` categories.
- Complete: category fandom lists load from `/media/<name>/fandoms`.
- Complete: fandom work lists reuse AO3 search with `work_search[fandom_names]`.
- Complete: saved/downloaded/favorite/finished local indicators are read-only.
- Complete: unsupported AO3 pages can use the read-only AO3 WebView fallback.
- Needs human review: WebView rendering, WebView back behavior, external browser
  handoff, and native Browse visual polish on device.

## Search

Status: Partial.

- Complete: global Search route, query field, sort control, loading/error/empty
  states, result cards, pagination, and canonical Work Detail routing exist.
- Complete: current AO3 sort enum remains unchanged.
- Deferred: advanced filter UI is not yet implemented on Android, though the
  underlying filter/query models exist.
- Needs human review: text input behavior, keyboard focus, and result density.

## Work Detail

Status: Partial.

- Complete: single Work Detail surface is used for local works and remote AO3
  summaries.
- Complete: local save, download/redownload, read, favorite, finished, user tag,
  collection, delete EPUB, remove from Library, and Open on AO3 actions exist.
- Complete: Phase 10 AO3 actions are surfaced: kudos, subscribe/unsubscribe, Mark
  for Later, AO3 bookmark create, and comments.
- Partial: direct raw AO3 work-id/URL native hydration is not implemented yet.
- Deferred: native AO3 bookmark edit/update and live AO3 write verification.

## Reader

Status: Partial, needs human review.

- Complete: Readium-based reader opens local EPUBs, restores progress, saves
  fallback progress fields, handles missing files, exposes comments when the work
  URL is known, and can mark finished.
- Complete: cross-platform resume still depends on `lastSpineIndex` and
  `lastScrollFraction`; engine-specific locators are same-platform precision only.
- Partial: full reader settings UI and custom font import are not finished.
- Needs human review: actual Readium rendering, progress persistence, TalkBack,
  and controls on device.

## Account

Status: Partial, needs human review.

- Complete: signed-in/signed-out/restoring/expired states exist.
- Complete: AO3 login uses AO3's real login page; Kudos never stores passwords.
- Complete: Marked for Later, AO3 Bookmarks, AO3 History, Subscriptions, and My
  Works lists exist where AO3 parsing supports them.
- Complete: Account links to Settings and Backup.
- Partial: account collections and dashboard are not fully native.
- Needs human review: live AO3 login/session behavior and list selectors.

## Settings And Backup

Status: Partial.

- Complete: Settings now displays current DataStore values for reader, privacy,
  and app settings using backup-contract field meanings.
- Complete: Settings can reset local settings to defaults and opens Backup.
- Complete: Backup screen states compatibility, merge-only restore behavior, and
  secret/session exclusion rules.
- Deferred: Android document picker import/export UI is not enabled yet.
- Needs human review: final settings controls, backup import/export UX, and copy.

## Accessibility And Platform Fit

Status: Partial, needs human review.

- Complete: app shell uses Material bottom navigation on phones and navigation rail
  on larger widths.
- Complete: Home work cards include concise semantics for title/author; major
  action buttons use visible text labels.
- Complete: key state is not color-only; local states are written as labels such
  as Downloaded, Favorite, Finished, and progress percentage.
- Partial: full TalkBack pass, focus traversal, font-scale clipping audit,
  keyboard behavior, and contrast review still require device/manual testing.

## Security, Privacy, And Release Readiness

Status: Partial.

- Complete: Android Auto Backup/data extraction excludes the app data root.
- Complete: Backup docs/UI state that AO3 passwords, cookies, CSRF tokens, and
  session files are excluded from `.kudosbackup`.
- Complete: WebView fallback policy is AO3-only in-app, externalizes other
  http(s), and blocks non-web schemes.
- Partial: release minification is not enabled, so R8 keep-rule smoke testing is a
  pre-release follow-up rather than an active release-build behavior.
- Needs human review: Google Play/F-Droid/GitHub distribution policy, AO3/OTW
  policy review, third-party notices, and live login/write smoke tests.

## Manual Parity Audit Gate

Status: Needs human review.

Recommended before declaring Android feature-complete:

- Run the app on a phone emulator/device and a tablet/foldable-size emulator.
- Check TalkBack, dynamic font scale, dark/light/sepia readability, and keyboard
  focus.
- Perform no-real-user-data backup import/export smoke tests once the document
  picker UI is enabled.
- Use a safe AO3 test account for login, account lists, kudos, subscribe, Mark for
  Later, bookmark create, and comments.
- Compare Home/Library/Browse/Search/Work Detail/Reader/Account surfaces against
  Apple for information hierarchy, not pixel shape.
