# Brief 3u Result: Library section lists (and Search's "In Your Library") as iOS draws them

The library section lists and the "In Your Library" section of the Search screen have been updated to use the full `SensitiveWorkRow` instead of the compact `WorkLedgerRow`.

## Key Changes
1. **Row Component Migration:**
   - Modified `SensitiveWorkRow` to accept both remote `AO3WorkSummary` and local `SavedWork` models via overloads, acting as a shared full-width work card.
   - Applied the full `SensitiveWorkRow` to `LibrarySectionScreen`, `SearchScreen` ("In Your Library"), and `CollectionDetailScreen`.
2. **Library Section UI Updates:**
   - Added section subtitles describing the count and the natural sort order (e.g. "most recently read first" for Reading Now).
   - Added uppercase section headers (`SectionRuleHeader`) grouping the visible items.
   - Migrated the toolbar actions (Privacy Toggle, Enter Selection) into a `⋯` (`MoreVert`) menu dropdown to match iOS, while preserving the original actions.
3. **Card Polish:**
   - Implemented iOS-style `SensitiveWorkRow` features for local works: favourite star visibility, fandom-tinted background blending based on the work title/fandom, and the "Tap to reveal" mature content privacy blur.

All functionality including swipe actions, the long-press context menu, selection mode, and bulk actions have been verified and preserved.
