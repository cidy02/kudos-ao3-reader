# UI Parity Checklist

Status: Phase 0 skeleton. Android UI should be native Android, but it must keep
the same product meaning, information hierarchy, and available actions.

## Navigation

Android target sections:

- Home
- Library
- Browse
- Account

Search is a global action, not a normal fifth content tab. Work Detail and Reader
are destinations reachable from the relevant flows.

## Information Density

Work cards and work detail surfaces should preserve or improve visibility of:

- title
- author
- fandom
- rating
- warnings/categories
- relationships/characters/freeforms where appropriate
- summary
- words
- chapters
- kudos
- comments
- hits
- saved/downloaded/favorite state
- completion state
- reading progress where relevant

Do not hide critical metadata behind extra taps unless the human approves the
tradeoff.

## Required Flows

Home:

- Continue Reading / Reading Now
- Recently Updated where available
- Favorites
- Recently Opened or reading history

Library:

- saved works
- downloaded/offline state
- favorites
- finished/unfinished
- user tags
- collections
- filters and sorting
- mature-content filtering

Browse:

- native browse by fandom/category
- tag/fandom work lists
- AO3 web fallback for unsupported pages

Account:

- login/session state
- Marked for Later
- AO3 Bookmarks
- AO3 History
- Subscriptions
- My Works where feasible
- settings and privacy/local-data actions

## Accessibility And Platform Fit

Android should use Compose Material 3 conventions:

- bottom navigation on phones
- navigation rail or adaptive layout on larger screens
- Android system back behavior
- Android document picker/share sheet
- Android BiometricPrompt/device credential behavior
- font scale accessibility

## Phase Gates

Phase 1 may use placeholders only. No AO3 networking, backups, reader, auth,
Room, DataStore, or parsing should be implemented in Phase 1.
