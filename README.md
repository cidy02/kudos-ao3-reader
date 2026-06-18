# Kudos — AO3 Reader

A personal, open-source (GPL-2) SwiftUI app for reading Archive of Our Own works
on iOS / iPadOS / macOS. Bundle id `devplaceholder.H17TULZJ.AO3_App_OpenSource`.

## Branch strategy

This repo tracks two versions of the app on two branches:

| Branch | What it is |
|---|---|
| `main` | **Stable legacy version.** The custom WKWebView + JavaScript reader with hand-rolled EPUB parsing (`MiniZip` / `OPFParser` / `NCXParser`). |
| `readium-migration` | **Ongoing migration** to the [Readium Swift Toolkit](https://github.com/readium/swift-toolkit). Replaces the custom reader/parsing piece by piece. |

Both versions live at the same paths; switch between them with Git:

```bash
git checkout main                # work on / build the stable legacy app
git checkout readium-migration   # work on / build the Readium migration
```

> Switching branches rewrites the working tree (e.g. the `readium-migration`
> branch adds `AO3_App_OpenSource/Features/ReaderReadium/` and the Readium SPM
> dependency). Anything you have in progress is on its branch — nothing is lost
> by switching.

## What's not tracked

See [`.gitignore`](.gitignore). In short: build output (`build/`, DerivedData),
per-user Xcode state (`xcuserdata/`, `*.xcuserstate`), `.DS_Store`, local tooling
config (`.claude/`), and working notes/prompts/scratch files
(e.g. `READIUM_MIGRATION_NOTES.md`). Dependency pins
(`…/xcshareddata/swiftpm/Package.resolved`) and the project file
(`project.pbxproj`) **are** tracked.

## Building

Open `AO3_App_OpenSource.xcodeproj` in Xcode and build the `AO3_App_OpenSource`
scheme. The `readium-migration` branch's Readium reader runs on iOS/iPadOS.

A Run Script build phase strips extended attributes from Readium SPM resource
bundles so that device builds and archives succeed (the provenance/FinderInfo
xattrs from SPM would otherwise block codesign).

Example command-line archive (then export or manual .ipa packaging):

```bash
xcodebuild -project AO3_App_OpenSource.xcodeproj -scheme AO3_App_OpenSource \
  -destination 'generic/platform=iOS' \
  -archivePath build/AO3.xcarchive archive \
  CODE_SIGNING_ALLOWED=NO
```

## Testing

Unit tests live in the `KudosTests` target (Swift Testing) and cover the
pure-logic core: the MiniZip reader, EPUB OPF metadata + NCX table-of-contents
parsing, HTML-entity decoding / summary stripping, and work-tag normalization.
A minimal hand-built `KudosTests/Fixtures/sample.epub` backs the EPUB tests.

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
