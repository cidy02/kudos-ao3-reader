# Core Behavior Contract

Status: Phase 0 skeleton. Android implementation must not start from this file
alone; use this together with `docs/android/ANDROID_PORT_PLAN.md` and the
current Apple reference implementation.

## Source Of Truth

Until contract tests exist, the Apple app on `main` is the behavioral reference.
The source root is `kudos-ao3-reader/`, not `AO3_App_OpenSource/...`.

Reference areas:

- `kudos-ao3-reader/App/`
- `kudos-ao3-reader/Models/`
- `kudos-ao3-reader/Services/`
- `kudos-ao3-reader/Reading/`
- `kudos-ao3-reader/Features/`
- `kudos-ao3-reader/Settings/`
- `kudos-ao3-reader/UIComponents/`
- `KudosTests/`

## Approved Android Branch

Android-port work uses `kudos-ao3-reader-android`. Do not commit Android port
implementation directly to `main`; `main` remains the Apple/reference branch for
this effort until the human approves a merge.

## Phase 0 Boundary

Phase 0 is documentation only:

- Android plan in `docs/android/ANDROID_PORT_PLAN.md`
- Contract skeletons in `docs/contracts/`
- Handoff notes in `docs/ai/HANDOFF.md`
- `TASKS.md` task tracking

Do not create Gradle, Compose, Room, DataStore, networking, backup, reader, auth,
or parser implementation in Phase 0.

## Compatibility Rule

Android can use platform-native UI and APIs, but these meanings must match the
Apple app unless a platform limitation is explicitly documented:

- saved work states
- AO3 search/filter URL generation
- AO3 parsing outputs
- AO3 request politeness, retry, and write safety
- backup import/export and merge semantics
- reader settings and progress semantics
- local user tags, collections, bookmarks, and saved searches
- mature-content privacy settings
- authentication/session handling rules

## Current Model Notes

Current Apple `SavedWork` uses non-optional integer sentinel values for several
stats:

- `comments: Int = 0`
- `hits: Int = 0`
- `knownChapterCount: Int = 0`

In the current Apple model, `0` means unknown/not yet populated for these fields.
Android may choose nullable Room columns internally only if import/export and UI
semantics preserve the Apple meaning.

Current Apple `Tag` has only a unique `name` and relationship data. Android
fields such as `TagEntity.dateCreated` are Android-internal or future additions,
not existing Apple parity fields.

Current Apple `WorkCollection` parity fields are:

- `id`
- `name`
- `dateAdded`
- `works`

Current Apple `SavedSearch` parity fields are:

- `id`
- `name`
- `dateAdded`
- `filters`

## Contract Test Direction

Future cross-platform tests should compare normalized semantic output, not raw
Swift/Kotlin JSON bytes. Normalize UUID case, date instants, optional defaults,
and numeric tolerances before comparing.
