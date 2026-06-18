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
