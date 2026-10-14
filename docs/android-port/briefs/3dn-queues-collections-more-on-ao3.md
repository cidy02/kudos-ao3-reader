# 3dn: Queues, Collections and More on AO3 beside the iPhone's (Android)

Done 2026-10-14 by Claude, alone. Gate 2,644. Pictures: `shots/3dn/`. Follows 3dm.

## Compared and the same

The Queues page (tiles, tag chips, rows), one queue's page (header, progress, chips, Up next,
In line), Collections. The demo libraries differ (iOS has a fifth queue, "Late").

## Fixed

1. **More on AO3's rows had no icons**; iOS puts its glyph before each row, in the accent.
   Each row has the nearest Material outlined icon now (square.and.pencil → Edit,
   checklist → Checklist, hand.raised → PanTool, and so on).
2. **A collection tile broke a long word across lines**: "Unanswere / d Is Not U…". iOS lets
   the title shrink to 85% before giving up (`minimumScaleFactor(0.85)`); Android's could
   not shrink. It steps down to 8 sp now, as iOS.
3. **Queue sizes were "2.1 KB", "8.3 KB"**: the Queues page, a queue's header and the My
   copy sheet had a formatter of their own. iOS writes them with the app's one formatter
   ("2 KB", "8 KB"), and so does Android now (`ReadingQueueFacts.byteCountString` →
   `LocalStorageFootprint.formatted`, as 3di did for the Settings pages).

Seen in Sepia, Dark and at 2.0×.

## Left

- iOS's queue rows end in a chevron; Android's do not.
- The gap between a collection's name and its count is wider on Android.
