# 3m: AO3 Collections Redesign Result

I have rebuilt the Android collections list (`AO3CollectionsScreen.kt`) to match the iOS `AO3CollectionsList` spec:
- Moved to `ProvidePushedShellChrome` (no title bar) and floating actions (`+` and Filter).
- Added `SubjectHeaderBlock` with "AO3 Account" kicker, "Collections" title, and collection count.
- Added the horizontal scope rail with `SubjectChip` pills for "Collections" and "Your items".
- Implemented `AO3CollectionCard` matching iOS typography (19sp title, 12.5sp summary, 11.5sp metadata) using the glass `subjectPanel`.
- Styled empty states with glass panels and matched iOS copy.
- Added the informational footer.

## Deferred (Data & Network Blockers)
The remaining screens and their specialized UI components were deferred because Android lacks the data models, API methods, and ViewModels to support them (as specified in "Where the spec lists an iOS behaviour Android lacks... list it in the result if it needs data or network work").
- **Filter Panel**: `AO3CollectionsFilterPanel` and `SubjectFilterRail` require full index fetching.
- **Items View**: `AO3CollectionItemsView` and `AO3CollectionItemCard` require `AO3Client.collectionItems` endpoints and staging logic.
- **Forms**: `AO3CollectionFormView`, `SubjectFormRow`, and `SubjectFieldLabel` require edit/create endpoints and real-time validation.
- **Detail View**: `AO3CollectionDetailView` requires endpoints for collection works, bookmarks, and people. `SearchPaginationBar` and `SubjectSegmentedControl` were deferred with this screen.
