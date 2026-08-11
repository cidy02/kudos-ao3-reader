# Reader State Contract

Status: Phase 0 skeleton. Android should use Readium Kotlin; do not port the
Apple legacy WKWebView reader.

## Reference Files

- `kudos-ao3-reader/Models/Models.swift`
- `kudos-ao3-reader/Features/ReaderReadium/ReadiumReaderView.swift`
- `kudos-ao3-reader/Features/Reader/ReaderView.swift`
- `kudos-ao3-reader/Features/Reader/ReaderStyle.swift`
- `docs/EPUBParsing.md`
- `KudosTests/ReadiumReaderTests.swift`
- `KudosTests/SavedWorkProgressTests.swift`

## Stored Progress Fields

Current shared Apple fields:

- `lastSpineIndex: Int`
- `lastScrollFraction: Double`
- `lastReadDate: Date?`
- `readiumLocator: String`

Future v2 backup fields should add locator metadata:

- `readiumLocatorPlatform`
- `readiumLocatorEngine`
- `readiumLocatorVersion`

## Portability Rule

`readiumLocator` is platform/engine-specific. It may support precise same-platform
restore, but it is not the cross-platform source of truth.

Cross-platform resume uses:

- `lastSpineIndex`
- `lastScrollFraction`

Android must continuously maintain those fallback fields whenever progress is
saved, even when it also stores a richer Readium Kotlin locator.

## Restore Rule

Restore order:

1. Use a compatible same-platform locator when metadata confirms it is safe.
2. Otherwise fall back to `lastSpineIndex` and `lastScrollFraction`.
3. If no useful progress exists, open at the beginning.

Apple should preserve Android locator strings during v2 import/export where
possible, but should not interpret Android Readium Kotlin locators as Apple
reader locators without an explicit compatibility decision.

## Reader Settings

Reader state must honor the settings contract:

- `readerFontID`
- `readerMode`
- `readerTwoPage`
- `readerCustomize`
- `readerBoldText`
- `readerFontPt`
- `readerLineHeight`
- `readerLetterSpacing`
- `readerWordSpacing`
- `readerMargin`
- `readerJustify`
- `readerTheme`
- `matchAppReaderTheme`

Android can map units to platform-native rendering, but backup values keep the
same semantic names and ranges unless a new backup version is introduced.

## EPUB Scope

Kudos targets unprotected AO3 EPUBs. EPUB files and backup ZIP entries are
untrusted input; future broadening of import scope must add containment,
compression, and active-content safety checks before accepting arbitrary EPUBs.
