# 3di: Reading Insights and the rest of Settings beside the iPhone's (Android)

Done 2026-10-12 by Claude, alone. Gate 2,635. Pictures: `shots/3di/`. Follows 3dh.

## Compared and the same

Recently Deleted. Privacy & Local Data, top to foot (Android also lists imported fonts).
Queue Storage. Reading Insights' "Your library" and "Most-read fandoms".

## Fixed

1. **Listening's three speeds were three lines of text down the panel.** iOS sets them
   side by side, the one in use dimmed. Android does now; at the large text sizes they
   stay lines.
2. **Two ways of saying a size.** Downloads and Queue Storage said "36.62 kB" and "8.29
   kB" (the platform's formatter); Privacy & Local Data, and iOS, say "37 KB" and "8 KB".
   One formatter now (`LocalStorageFootprint.formatted`).
3. **Insights' big figures were in monospace**, so "6 hours ago" was typewriter text beside
   its numbers. iOS sets the big figures in the page's own face and keeps monospace for the
   small ones that line up (bar values, the change since last month, a fandom's hours).
   Android does now.

Seen in Sepia; Listening also in Dark and at 2.0×, and beside the iPhone's. A speed tapped.

## Found, not fixed: "words per hour" (owner question 27, both apps)

A reading session stores its work's **whole** word count, and "words per hour" is those
counts added up and divided by the hours read (`ReadingInsights.wordsPerHour`, the same
on iOS and Android). So every sitting counts the whole work however little was read. One
look of 22 seconds at an 18,000-word work showed **"2,977,444 words per hour"** on the
emulator. A 100,000-word work read in ten sittings of an hour shows 100,000 words per
hour, ten times the truth. Counting what was read in each sitting (the change in position
since the sitting before, times the work's words) would say what the label says. It is a
change to what a figure means, on both apps, so it is put to the owner.

## Left

- Appearance has line height, letter spacing and word spacing on Android only.
- Android's Insights showed "This month" where iOS's demo said "No reading logged this
  month": the emulator had one short sitting logged from an earlier test, not a difference.

## Not checked

- The Availability sweep's own page; "Customize Theme…".
