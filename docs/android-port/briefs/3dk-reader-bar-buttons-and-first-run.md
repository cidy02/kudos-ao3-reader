# 3dk: the reader's bar buttons; first-run screens and Check Availability beside the iPhone's

Done 2026-10-12 by Claude, alone. Gate 2,639. Pictures: `shots/3dk/`. Follows 3dj.

## The reader's back and fan buttons (owner, 2026-10-12)

> the back button inside the reader is inconsistent with others in the app. in placement
> and icon. the fan menu button to the right of it is gray rather than white, so bring
> that one to consistency with the rest of the UI as well

Seen on the iPhone, and fixed there as T-403: the reader drew its own back button 12pt in
and 8pt low with a chevron a third smaller than a navigation bar's, and the fan mark came
out at about 30% strength because the glass was drawn over it.

**Android had the first half of it.** The reader's back button was a 44dp circle 12dp from
the edge with a 17dp arrow; every other page has Material's icon button 4dp in and 6dp
under the status bar with a 24dp arrow. So the arrow sat 6dp further in and 4dp higher
than everywhere else, and smaller. Both of the reader's round buttons are now that icon
button in that place (`ReaderChromeButton`: 48dp to touch, a 24dp mark), on a 40dp
backing because they float over the page's text. The fan menu opens out of the same spot.
Android's fan mark was already solid.

Seen beside a work's page in the four app themes; the menu opened and closed.

## First-run screens, What's New, Check Availability

Compared with the iPhone's and the same in content and order. One thing fixed: the page
titles ("Welcome to Kudos", "Protect Your Library") were in the body's weight; bold now,
as iOS.

## Also

- The tick beside the chosen pseud (3dj) was the raw accent, dark red on OLED's black. It
  is the palette's accent now, which reads on every theme.

## Left

- "Don't remind me again" is a checkbox on Android and a switch on iOS: Android's own.
- What's New is a short sheet on Android and a full one on iOS.
- Check Availability is a page on Android and a sheet on iOS. Nothing was started on it.

## Found, not changed: "Customize Theme…" (owner question 29)

On Android's Appearance page the row opens the accent colour's presets, the same thing
as the "Accent Color" row above it. On iOS it opens the reading-text sheet: a sample
page, the four themes, Font, Bold Text, a Customize switch, line, character and word
spacing, margins, Justify Text, Reset Theme. Android has most of those controls spread
over Appearance, Reader and Font, and Bold Text only inside the reader. It is the
reader's controls (owner question 12), so it is put to the owner.

## Not checked

- The reader's bar in the reader's own Sepia, Dark and OLED (the demo's reader stays Light
  whatever the app's theme; the buttons' colours were not touched).
- `nav:welcome` with the OLED theme showed Home, not the Welcome page: a quirk of the demo
  route, not looked into.
