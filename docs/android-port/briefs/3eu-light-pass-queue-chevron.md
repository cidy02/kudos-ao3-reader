# 3eu: a Light pass; queue rows say they open (Android)

Done 2026-10-15 by Claude. Gate 2,673. Pictures: `shots/3eu/`.

- **Light beside the iPhone's:** Browse, Search results, Queues and Collections: the same.
- **Changed:** the iPhone's queue rows end with a chevron (its list draws one on every row that
  opens a page); Android's had none, though its other opening rows (sign-ups, settings) have
  one. Queue rows show it now, except while selecting or reordering. Seen on the emulator.

**A37 F3 left, recorded:** a read that bypasses the cache after a write can join a read of the
same page begun before the write and take its older answer. Fixing it means telling the
transport which reads must not join, through every repository's fetch; the race needs the same
page in flight at the moment of the write, and iOS's coalescing has the same shape. Not done.
