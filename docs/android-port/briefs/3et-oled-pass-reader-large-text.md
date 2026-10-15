# 3et: an OLED pass, the reader at double text size, and an author page's loading card (Android)

Done 2026-10-15 by Claude. Gate 2,673.

- **OLED beside the iPhone's:** Browse, Search results and Queues: the same. (iOS's
  `comments` debug route opens a sample screen of its own, so Comments did not compare.)
- **The reader at font scale 2.0:** the bar, the fan menu and its round actions, Contents and
  the position card all hold; nothing cut off.
- **Fixed:** an author page's "Loading author profile" card sat under the back button: every
  other state of the page starts below the status bar and the bar, and this one did not. It
  does now. (Too quick to catch on the emulator; the change is the same spacer.)

Process note: one launch tonight skipped the demo flags (a bare `am start`); the emulator was
in airplane mode, so nothing could reach AO3. Use `open_route` only.
