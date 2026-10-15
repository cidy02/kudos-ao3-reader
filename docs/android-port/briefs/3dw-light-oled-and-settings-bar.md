# 3dw: Light and OLED beside the iPhone's; Settings' first opening (Android)

Done 2026-10-14 by Claude, alone. Gate 2,648. Pictures: `shots/3dw/`. Follows 3dv.

## Light and OLED

Home, Library, Account, Settings and a saved work's page, in Light and in OLED, beside the
iPhone's. The same in both themes but for one fault, below.

## Fixed: Settings first opened under a plain top bar (a regression of 3dh)

Opened from Account or by a link, Settings showed a solid bar ("Settings" and a theme
button) over an empty band, above its own heading; after visiting a page and coming back
it was right. 3dh wrapped Settings in `ProvidePushedShellChrome(hasSubjectHeader = null)`,
and that is re-applied each time the screen recomposes, after the hub had said it has a
header. Every page in Settings draws its own header, so Settings says so itself now
(`hasSubjectHeader = true`). Seen: by link, from Account, into Appearance and back.

## Not a difference

Settings › Appearance says "Sepia" while the emulator shows Light: the launch extra that
picks the theme for a picture does not change the saved setting.
