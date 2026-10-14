# 3dt: the Account hub beside the iPhone's; one avatar (Android)

Done 2026-10-14 by Claude, alone. Gate 2,648. Pictures: `shots/3dt/`. Follows 3ds.

## Compared and the same

The Account hub top to foot: header, Posting as, Shortcuts, Reading, Writing, Activity,
Account. The 10-11 notes no longer hold: the Collections and Series glyphs read alike, and
"6+" against "4+" on Subscriptions is the two demos' subscription counts, not an Android-only
badge.

## Fixed: the avatar's fallback

iOS draws every avatar with one view, `AO3AuthorAvatar`: the image when it loads, otherwise a
person glyph at 42% of its size over a quiet fill (round on the Account header, square on an
author's page). Android had three fallbacks: the Kudos mark on the Account header and the
signed-out card, and a blank square on an author's page. One shared `AO3AuthorAvatar` now,
as iOS's. The header's avatar is still spoken as "View Profile".

Seen in Sepia and Dark.

## Not a difference

The iPhone's demo shows a picture in its Account header and Android's none: the demo pages
point at AO3's default icon, which neither demo serves (they never go online).
