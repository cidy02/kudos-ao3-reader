# 3ds: dead account-list code removed (Android)

Done 2026-10-14 by Claude, alone. Gate 2,648. Follows 3dr's hunt for stand-ins.

`AccountScreen.kt` held five functions nothing called (`HubWorksPane`, `HubCollectionsPane`,
`AccountListScreen`, `AccountListContent`, plus `EnrichingSensitiveWorkRow` and
`PaginationControls` once those were gone): an older account list and hub panes, replaced
by `AccountWorksListScreen`. They drew Library cards whose menu actions did nothing
(`onToggleFavorite = { }`, `onToggleFinished = { }`, `onRemove = { }`, "Later: pair tags
too"). Unreachable, so no one met them, but a later change could have wired them back in.
476 lines removed; the view model and state they shared serve the live list and stay.
Compiles; every test passes.
