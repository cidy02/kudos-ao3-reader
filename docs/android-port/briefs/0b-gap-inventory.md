READ-ONLY audit. Do not edit, create or delete files. Do not run git commands that write, and do not build or touch the network.

Repo: `/Users/cidy02/kudos-android-redesign`. It holds both apps:
- iOS (the reference, SwiftUI): `kudos-ao3-reader/`. Its feature map is `docs/ARCHITECTURE_MAP.md`.
- Android (Kotlin + Jetpack Compose): `android/app/src/main/java/io/github/cidy02/kudos/`.
- Design spec: `docs/design/Final_Redesign_Spec.dc.html` (artboards are `<div class="dv-opt" id="1xx">`).
- Mission and parity matrix: `docs/android-port/LIVING-PROMPT.md`, §7.

Goal: list what Android is missing or does differently, area by area, so the port can be planned. Cover every row of the §7 matrix: Home, Library, queues, collections, Recently Deleted, Reading Insights, Browse, Search and filters, Work detail, Reader, Comments, the Account hub, bookmarks/history/subscriptions, Inbox, authors and dashboard, AO3 collections, challenges, Writing, AO3 Preferences, Settings, More on AO3, onboarding and support, and data parity (models, backup manifest, sync).

For each area:
1. **Screens.** Each iOS screen (file) and whether Android has an equivalent (file), partly or not at all.
2. **Behaviours.** Actions and states iOS offers that Android lacks. For example: long-press menus, swipes, select mode, the filter panel, Edit Queue, custom colours (`colorHex`), "Downloaded" meaning kept (`SavedWork.isDownloaded`), "Keep works you read", the download ring, Recently Deleted's 60-day held copies (`freedAt`), and Remove Download only un-keeping.
3. **Model and data.** iOS model fields and services with no Android counterpart (Room entity or column, repository).
4. **Redesign state.** Whether the Android screen already uses the redesign's look (kicker, rule and header block, subject wash, cards, chips, stat strip, progress ring) or the older one.

Output one markdown document, organised by area, with a table per area:

| iOS (file) | Android (file or "none") | Gap | Size (S/M/L) |

End with:
- the ten largest gaps;
- shared building blocks Android lacks that many screens need (theme tokens, `SubjectPalette`, components);
- anything Android has that iOS does not.

Cite only what you read, and mark anything unsure. Keep it under 3,500 words.
