TASK: four small, well-bounded edits in this SwiftUI app (Kudos). Edit files only; do NOT run xcodebuild, git
commit, git add, or touch AO3_App_OpenSource.xcodeproj. Never contact any network service. When done, list every
file you changed and, per item, what you did. Match the surrounding code's style and comment density.

1. List row minimum (pattern already used in WorkEditView.swift, SeriesEditView.swift, WritingChaptersView.swift):
   directly after `.cardList()` add
       // Rows at their own padding, not the List minimum (L3-FORM-1).
       .environment(\.defaultMinListRowHeight, 0)
   in: kudos-ao3-reader/Features/Writing/WritingDraftsView.swift (the `.cardList()` near line 117),
   kudos-ao3-reader/Features/Writing/WritingPreviewView.swift (near line 56), and each of the four `.cardList()`
   calls in kudos-ao3-reader/Features/Writing/WorkAssociationPickers.swift (near lines 87, 413, 549, 657).
   Do not add it anywhere else.

2. Dead parameter: `SubjectHueSwatchRow` (kudos-ao3-reader/UIComponents/SubjectHueSwatches.swift) has a
   `fallbackHue` property whose doc comment promises a ring that nothing draws. Delete the property and its doc
   comment, and remove the `fallbackHue:` argument from every caller (grep `SubjectHueSwatchRow(`: NewCollectionSheet,
   NewReadingQueueSheet, Collections.swift). If a caller computed a value only to pass it there, remove that too
   only if nothing else uses it.

3. New collection sheet (kudos-ao3-reader/Features/Library/NewCollectionSheet.swift): under the swatch row, the New
   queue sheet (NewReadingQueueSheet.swift ~line 92) explains the no-colour state with a footnote. Add the same
   explanation to the collection sheet using that sheet's existing footnote style (it already has footnotes —
   reuse the same view/modifier it uses for them):
       hue == nil → "Without a colour, the collection takes one from its name — and changes it if you rename it."
       otherwise  → "Set once, so renaming the collection keeps its colour."
   Check first whether a collection's colour really follows its name when unset (look at how the collection's hue
   is derived when `hue` is nil, e.g. `CoverArt.hue(for:)`); if renaming does NOT change it, use
   "Without a colour, the collection takes one from its name." for the nil case instead, and say which you used.

4. Offline fixture for the Prompt Meme screen (DEBUG harness): `PromptMemeView` loads
   `/collections/<slug>/requests` via `AO3Client.promptMemePrompts` → `parsePromptMemePage`
   (kudos-ao3-reader/Services/AO3Client+Challenges.swift ~line 491). Read that parser fully, then:
   a. create kudos-ao3-reader/../KudosTests/Fixtures/ao3_prompt_meme_requests.html — a small AO3-shaped page the
      parser accepts, with 4 prompts: 2 unclaimed, 1 claimed by someone else, 1 claimed by the signed-in demo user
      "AO3_Reader"; realistic fandom/character/relationship tags; one prompt anonymous;
   b. add a route line `("^/collections/[^/]+/requests", "ao3_prompt_meme_requests"),` to `DemoNetworkBlock.routes`
      in kudos-ao3-reader/App/DemoLibrary.swift, placed before the `("^/collections/[^/]+/?$", …)` line;
   c. add `<li><a href="/collections/winter_exchange/requests">Prompts</a></li>` to the navigation list in
      KudosTests/Fixtures/ao3_collection_show.html so the collection page shows a Prompts row.
   Also add ONE Swift Testing test in a new file KudosTests/PromptMemeFixtureTests.swift that loads the fixture
   (copy how KudosTests/AO3ChallengeParsingTests.swift loads fixtures) and asserts parsePromptMemePage returns 4
   prompts. Keep it to one test.
