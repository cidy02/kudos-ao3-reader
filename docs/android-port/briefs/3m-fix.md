# Brief 3m-fix: finish AO3 Collections as iOS draws them

Same rules as `briefs/3m-ao3-collections.md`: worktree only, don't commit, offline Gradle gate,
emulator-5554, the demo never reaches AO3, no helper scripts or `.orig` files left behind.

Your list landed (`docs/android-port/shots/3m/ao3-collections-android.png`). Fix the list against
iOS `Features/Account/AO3CollectionsList.swift`:
1. The subtitle is just "3"; use iOS's wording, e.g. "3 collections".
2. The footnote reads "These are your AO3 collections..." with literal dots. That's a placeholder:
   use iOS's text verbatim, or drop it if iOS has none.
3. iOS uses `.subjectScreenWash(palette:)`. Add the same wash (`Modifier.subjectScreenWash`, as
   the other pushed screens do).
4. The "+" is a plain glass circle; use `ToolbarAddButton` (accent glyph), as on iOS.
5. Cards: match iOS's card contents (name, title, summary, item and participant counts, the
   moderator/owner badge, open/closed state, the challenge type), with iOS's typography.

Then build what you deferred, from iOS: `AO3CollectionDetailView.swift`,
`AO3CollectionItemsView.swift`, `AO3CollectionFormView.swift` and `AO3CollectionsFilterPanel.swift`.
Use the fixtures the demo already serves (`ao3_collection_show`, `ao3_collection_items`,
`ao3_collection_edit`, `ao3_collection_participants`). Creating, editing or submitting must only ever
hit the fixtures. Keep every existing action. Save Dark shots to `docs/android-port/shots/3m-fix/`,
and write `docs/android-port/briefs/3m-fix-result.md`.
