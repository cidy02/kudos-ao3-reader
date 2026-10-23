# I13 result (iOS): Add Works' bylines at the largest text

*Done.* Branch `claude/agent-ios-i13` from `7d58eebd`. Nothing committed. One file changed: `kudos-ao3-reader/Features/Library/AddLibraryWorksSheet.swift`.

## Why it cut

- The byline sat in a column beside the selection circle.
- At AX5 that column was about 245 pt wide, too narrow for "by uncle_iroh_fan": one AO3 name with no space to break at, about 300 pt at the caption size.
- The name broke mid-word ("un- / cle_iroh"), and the shared byline's two-line cap then cut it with "…".
- The app's other work rows use the same byline the same way at the accessibility sizes: not compact, up to two lines. They give it the row's full width, so it fits.

## The change

- **At the accessibility sizes, the selection circle goes under the title and byline** (`AddLibraryWorksSheet.swift:137`, `AnyLayout`). The byline then has the row's full width and reads whole: "by uncle_iroh_fan" fits on one line at AX5, by measurement from the A88 tile.
- This is the reflow I9 gave the collection reorder rows (`NewCollectionSheet.swift:313`). The spacer only applies beside the circle (`:158`).
- **Below the accessibility sizes, nothing changes:** the circle stays trailing.

**Left as is:**
- The shared `AO3AuthorBylineView` and its two-line cap. Lifting the cap would also change the bylines on Home's resume hero and Work Detail at every accessibility size, and those can't be checked here.
- At full width, two lines hold 30-odd characters of one name at AX5. A longer single-word name would still break mid-word, since there is nowhere else to break it, but it would no longer end in "…".

**Unchanged and checked:**
- I12's content heading ("Add to \(destinationName)", `:71`, unlimited lines) is outside the row.
- The count and Add (`:118`) still use `chosen`.
- VoiceOver still reads the row as one element, with its selected value and hint.

## Build and lint

- **iOS:** arm64 simulator, `…/kudos-agent-ios-ios`, BUILD SUCCEEDED. **macOS:** `…/kudos-agent-ios-mac`, BUILD SUCCEEDED.
- **Warnings:** none in the file.
- **SwiftLint:** the file lints clean, as it does at HEAD.
- **Not run:** tests, the simulator. The re-shoot of `addworks` at AX5 is the check.
