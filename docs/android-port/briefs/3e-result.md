# 3e result — Recently Deleted & local collections

Redesigned Recently Deleted and local collections to achieve visual and behavioral parity with iOS.

## Features & Changes

- **ToolbarAddButton (`ui/subject/SubjectComponents.kt`)**: Updated to a 44dp filled accent circle with a white plus glyph (`17.sp.asDp()`) and optional `SubjectPalette`, matching iOS across all screens. Added `SubjectAmber` (`#FFA00A`) and `WorkSelectionBubble`.
- **Recently Deleted (1bj, `library/RecentlyDeletedScreen.kt`)**: Redesigned with `SubjectHeaderBlock`, reassurance card, and two sections: "Deleted" (90 days) and "Finished, not kept" (60 days) with exact iOS section notes. Rows show days left (urgent `SubjectAmber` if < 7d). Full swipe actions (Restore & Delete/Remove), long-press menu, bulk Select in "…", bottom selection bar, and outlined red capsule "Delete All Permanently" button. All dialog messages match iOS copy exactly.
- **Collections Screen (`library/CollectionsScreen.kt`)**: Integrated `ToolbarAddButton` in pushed chrome and replaced bare text alert with `CollectionEditorSheet`. Card long-press confirms deletion with 90-day retention copy.
- **Collection Page (`library/CollectionDetailScreen.kt`)**: Wrapped in collection's wash (`subjectScreenWash`). Displays `SubjectHeaderBlock` with kicker "Library", title, and subtitle tally ("X works · kept offline"). Works sorted in reader order via `HomeFacts.inReadingOrder`. Supports detailed and ledger display modes, swipe-to-remove, more menu (Select, Reorder, Display Mode, Rename, Details, Delete), and multi-select bottom bar.
- **New / Edit Collection Sheet (`library/CollectionEditorSheet.kt`)**: Unified sheet matching 1bk. Name, description, five swatches plus dashed "+" HSV picker (storing exact `colorHex`), `SubjectToggle` for Keep downloads and Show on Home, dynamic wash following the chosen colour, and iOS footnote strings.
- **Collection Reorder Sheet (`library/CollectionReorderSheet.kt`)**: Reorders collection works with deferred commit on Done (`workRepository.setCollectionReadingOrder`).
