# Kudos — AO3 Reader

A native macOS / iOS / iPadOS reader for Archive of Our Own with a polished
Liquid Glass experience. Personal and open-source (GPL-3.0), built with SwiftUI
and SwiftData.

## Features

- **Read AO3 works offline** — download a work's EPUB and read it in a native
  paginated or scrolled reader, with Light / Sepia / Dark themes and custom
  typography (font, size, line/letter/word spacing, justification, margins).
- **Native AO3 search & browse** — a faceted works search, browse-by-fandom, and
  an in-app AO3 web view; scraped politely with SwiftSoup (AO3 has no public API).
- **Secure AO3 account session** — native login backed by AO3's real form, with
  hidden-WebView session capture, automatic visible fallback, and device-only
  Keychain persistence as the foundation for future account sync.
- **Library & bookmarks** — saved works with rich metadata (rating, word count,
  chapters, kudos, series), custom tags, filtering, reading history, and favorites.
- **Portable backups and folder sync** — export Library records, EPUBs, tags,
  bookmarks, custom fonts, and settings to a versioned `.kudosbackup` package;
  imports merge safely, and an optional Library Sync Folder can keep
  `KudosLibrary.kudosbackup` in iCloud Drive or another user-selected folder.
- **Privacy-aware** — mature works can be hidden behind a Face ID gate.
- **Cross-platform** — one SwiftUI codebase for iPhone, iPad, and Mac.

## Branch strategy

Single branch: **`main`**. (The project previously tracked a `main`/`readium-migration`
split during the reader migration; those were consolidated into `main` in June 2026.)

The reader uses the [Readium Swift Toolkit](https://github.com/readium/swift-toolkit)
on **iOS/iPadOS**, and the original custom WKWebView + JavaScript reader (with
hand-rolled `MiniZip` / `OPFParser` / `NCXParser` parsing) on **macOS** — Readium's
navigator is UIKit-only, so macOS keeps the legacy reader. `BookReaderView` routes
to the right one per platform.

## What's not tracked

See [`.gitignore`](.gitignore). In short: build output (`build/`, DerivedData),
per-user Xcode state (`xcuserdata/`, `*.xcuserstate`), `.DS_Store`, local tooling
config (`.claude/`), and working notes/prompts/scratch files
(e.g. `READIUM_MIGRATION_NOTES.md`). Dependency pins
(`…/xcshareddata/swiftpm/Package.resolved`) and the project file
(`project.pbxproj`) **are** tracked.

## Building

Open `AO3_App_OpenSource.xcodeproj` in Xcode and build the `AO3_App_OpenSource`
scheme. The Readium reader runs on iOS/iPadOS; for Simulator builds from the
command line, code signing can be disabled:

```bash
xcodebuild -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO build
```

## Testing

Unit tests live in the `KudosTests` target (Swift Testing) and cover the
pure-logic core: the MiniZip reader, EPUB OPF metadata + NCX table-of-contents
parsing, HTML-entity decoding / summary stripping, and work-tag normalization.
Search-filter tests also cover advanced rating query generation, tag and facet
exclusions, and the include/exclude/clear cycle. Authentication tests cover
cookie scoping, session restoration and expiration, hidden login outcomes, and
automatic fallback. Backup tests cover package round-tripping, merge restoration,
and unsupported format versions. A minimal hand-built
`KudosTests/Fixtures/sample.epub` backs the EPUB tests.

```bash
Scripts/test.sh        # runs on the default iOS Simulator
# or directly:
xcodebuild test -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource \
  -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO
```

## Linting & formatting

[SwiftLint](https://github.com/realm/SwiftLint) is the linter; [SwiftFormat](https://github.com/nicklockwood/SwiftFormat)
is an optional formatter. Install both with Homebrew:

```bash
brew install swiftlint swiftformat
```

Run the checks (SwiftLint is the gate; it currently reports warnings only, so it
exits cleanly — fix them opportunistically):

```bash
Scripts/lint.sh          # check
Scripts/lint.sh --fix    # apply SwiftFormat + SwiftLint autofixes in place
```

Config lives in [`.swiftlint.yml`](.swiftlint.yml) and [`.swiftformat`](.swiftformat).
SwiftFormat is kept advisory: the codebase is wrapped by hand, so it is **not**
enforced and no bulk reformat has been applied — run `--fix` only when you want it.

To surface lint warnings on staged files before each commit (non-blocking):

```bash
git config core.hooksPath .githooks
```

CI ([`.github/workflows/ci.yml`](.github/workflows/ci.yml)) runs SwiftLint on every
push/PR and activates once a remote is added. A build job is omitted until
GitHub runners ship the iOS 26 / Xcode 27 SDK.

You can also add SwiftLint as an Xcode build phase manually (Target ▸ Build
Phases ▸ + ▸ New Run Script Phase):

```bash
if which swiftlint >/dev/null; then swiftlint; else echo "warning: SwiftLint not installed"; fi
```

## Project docs

Planning and tracking notes live in [`TASKS.md`](TASKS.md) and [`docs/`](docs/):

- [`docs/PROJECT_PHILOSOPHY.md`](docs/PROJECT_PHILOSOPHY.md) — the canonical
  product direction, design/engineering principles, and contributor guidance.
- [`TASKS.md`](TASKS.md) — the single task board: backlog, completed work, and the
  consolidated **Bugs (BUG-N)**, **Feature Ideas (FI-N)**, and **UI Polish (UI-N)**
  registries (these replaced the former `docs/Bugs.md`, `Feature_Ideas.md`, and
  `UI_Polish_Todo.md`).
- [`docs/Kudos_Layout_Structure.md`](docs/Kudos_Layout_Structure.md) — navigation
  and layout model (Home / Library section structure).
- [`docs/AO3Authentication.md`](docs/AO3Authentication.md) — login, session,
  security, and authenticated-request architecture.
- [`docs/EPUBParsing.md`](docs/EPUBParsing.md) — supported EPUB structures,
  parser/import assumptions, failure behavior, and branch differences.
- [`docs/iCloudPersistence.md`](docs/iCloudPersistence.md) — no-entitlement
  Library Sync Folder architecture, migration, merge rules, EPUB asset strategy,
  and manual iCloud Drive test checklist.

## License

Released under the **GNU General Public License v3.0** — see [`LICENSE`](LICENSE).

This project scrapes Archive of Our Own's public HTML (AO3 has no official API).
It is an unofficial, personal project and is not affiliated with or endorsed by
the Organization for Transformative Works or Archive of Our Own.
