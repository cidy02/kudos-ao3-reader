# 3dr: a hunt for values fixed in place (Android)

Done 2026-10-14 by Claude, alone. Gate 2,648 (+1). Follows 3dq.

3dq's Browse fault was a value captured once and never refreshed. Looked for the same and
for its cousin, a stand-in left with a note ("for now", "we don't have").

## Found and fixed

1. **Settings › Font always said "System".** The hub's row was a constant ("We don't have
   direct access to font name string without repo, but it's ok for hub"). It names the chosen
   font now, imported ones too (`ReaderFontCatalog.name`; tested); a font no longer present
   reads as System, as iOS. Seen: Georgia chosen, the hub said Georgia; System again, System.
2. **Your own author page offered to subscribe to, mute and block yourself.** The hero was
   always told it was not your own profile ("assuming false for now"). It compares the
   signed-in account with the page's, as iOS. Not seen on the emulator: your own Works tab
   draws its own header; the hero is on the other tabs.

## Looked at and fine

- The only other `snapshotFlow` was Browse's (3dq). The only other long-running
  `LaunchedEffect(Unit)` (Settings hub) reads nothing stale.
