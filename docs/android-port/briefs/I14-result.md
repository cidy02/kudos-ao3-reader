# I14 result (iOS): A88b's iPhone items

*Done.* Branch `claude/agent-ios-i14` (from the I13 record). Nothing committed. Four files under `kudos-ao3-reader/Features/`.

## 1. `colsfilter`: Reset no longer shows the last option through it

- **Cause:** I10's ground faded evenly from the bar's foot to its top. The button sits in the middle of the bar, so its top half was over nearly clear ground. A bordered button's own fill is see-through, so "Unrevealed" showed through it at AX5.
- **Change:** the ground is now fully opaque behind the button. It fades only in the 12 pt of padding above it: a 12 pt gradient strip over a solid fill (`Account/AO3CollectionsFilterPanel.swift:175`).
- **Unchanged:** the colour (the page's `cardBackdrop`) and the bar's size.

## 2. `colitems`: the creator is shown whole

- **Cause:** "AO3_Reader (Member)" shared one row with "Remove from collection" and the date, which don't shrink. It got the leftover width and was cut to "AO3_Reader…".
- **Change:** the byline now takes its own line, unlimited, above Remove and the date (`Account/AO3CollectionItemsView.swift:790`; the action row is `:804`, the same as before). At the accessibility sizes the action row still stacks, as before.

## 3. `parentpicker`: the URL is not hyphenated when it wraps

- **Change:** the URL field takes the typesetting language "zxx" (no linguistic content) (`Writing/WorkAssociationPickers.swift:711`).
- **Why:**
  - The field hyphenated the address as English text ("archiveo- fourown.org"), adding a hyphen that reads as part of it.
  - Hyphenation follows the text's language. `CFStringIsHyphenationAvailableForLocale` is true for "en" and false for "zxx" (checked with a throwaway script). So the URL still wraps at the field's width, without an added hyphen.
  - SwiftUI has no hyphenation modifier. `typesettingLanguage` (iOS 17+, macOS 14+) is its control for line-breaking language.
- **Unconfirmed:** that the text field applies `typesettingLanguage` to its text view. That needs the AX5 re-shoot.
  - If it still hyphenates, the fallback is a small `UIViewRepresentable` text view with `hyphenationFactor = 0`.
  - That's a bigger change (sizing, focus and Return handling), so I didn't start with it.
- The page's header subtitle, a `Text`, already wraps the URL without a hyphen.

## 4. Shot routes `chsettingsedit`, `tagset`, `tagseteditor` at AX5

- **Cause:** the shot's push to Challenge Settings hung on the manage row's background. At AX5 that row is below the fold, and a `List` never builds a row it hasn't shown, so the push never happened.
- **Change:**
  - The manage screens are now a list of entries, each a label and a destination (`Account/AO3CollectionDetailView.swift:596`, `struct ManageEntry` at `:701`). The rows are drawn from those entries (`:677`).
  - In DEBUG, the page itself pushes the entry a shot names (`debugManageEntry`, `:683`, through `.navigationDestination` at `:126`), so it doesn't depend on the row being on screen.
  - The row-level debug push is removed.
- **Covers:** every shot that uses `manageRow`, not only these three. Their later pushes (`chsettingsedit` / `tagset` from Challenge Settings, `tagseteditor` from Tag set) were already page-level `.task`s and are unchanged.
- **Release builds are unchanged:** the same rows, gating and links.
- To stay under `type_body_length`, the manage block moved into the file's existing `extension AO3CollectionDetailView` (`// MARK: Manage`), with no change in code. That is most of this file's diff.

## Build and lint

- **iOS:** arm64 simulator, `…/kudos-agent-ios-ios`, BUILD SUCCEEDED. **macOS:** `…/kudos-agent-ios-mac`, BUILD SUCCEEDED. Both rebuilt after the last edit.
- **Warnings:** none new. `AO3CollectionItemsView.swift:149` ("'where' only applies to the second pattern…") is in untouched code and predates this change; it shows because the file recompiled.
- **SwiftLint:** all four files lint as at HEAD (0 findings). The block move above keeps `AO3CollectionDetailView` under `type_body_length`.
- **Not run:** tests, the simulator. The check is re-shooting `colsfilter`, `colitems`, `parentpicker`, and `chsettingsedit` / `tagset` / `tagseteditor` at AX5.
