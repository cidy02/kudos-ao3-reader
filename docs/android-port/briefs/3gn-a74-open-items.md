# Brief 3gn: the open items from A74 (old audit lists A14 and R1, checked 2026-10-22)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests, looks on the emulator and lands it. Do not edit
`TASKS.md`. Create `docs/android-port/briefs/3gn-result.md` FIRST and write each item into it as
you finish it: **fixed / already done / intentional difference (why)**, the Android `path:line`,
the iOS `path:line` you followed, and the test. This branch already holds 3gm (`0b36e448`);
build on it.

Grok checked every item of two 2026-10-08 audits against today's code; its evidence is in
`/Users/cidy02/kudos-agent-grok/docs/android-port/audits/A74-result.md` (sections 1, 2 and 3). Claude
spot-checked it: one claim was wrong (Account's Series row does open the native series screen,
`app/AppNavHost.kt:567`), so verify each item in the code before changing it. iOS source:
`/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Match iOS's words exactly (Android chrome stays).

1. **Account shortcuts: Series.** iOS's shortcut catalog has `series` (`Features/Account/
   AccountShortcuts.swift:16`, `:33`) opening the account's own series (`AccountView.swift:674`).
   Android's `account/AccountShortcuts.kt` enum lacks it ("My series is not implemented yet",
   now false). Add it, opening the same native destination the Account page's Series row uses.
   Saved shortcut lists that predate it must still read (the store's ids, `"none"`, defaults).
2. **Tag picker, no fandom chosen.** iOS `Features/Search/TagSelectField.swift:254-264` adds
   "Choose a fandom to see its most-used {title} here." under "Type above to search AO3
   {title}." when the query is empty, the kind is not fandom and no fandom is set. Android
   `search/FilterTagPicker.kt:165-167` shows only the first sentence.
3. **Comment composer while checking.** iOS shows "We're checking whether this posted before
   trying again…" while it verifies an unconfirmed post (`Features/Comments/CommentsView.swift:
   1609-1611`); Check Again re-reads and never posts. Android's verify (`comments/
   CommentsViewModel.kt:803-834`) shows nothing while it runs. Show iOS's sentence for the
   duration, where iOS shows it; keep every existing rule about never re-posting.
4. **Subscribe to an author while signed out.** iOS `Features/Authors/AuthorProfileView.swift:
   127-152`: alert "Log in to AO3", "Log in to your AO3 account to do this.", Cancel / Log In
   (opens login). Android sends the request and reports "AO3 requires login." Ask first, as iOS.
5. **History and Subscriptions signed out.** iOS `Features/Bookmarks/AO3AccountWorksList.swift:
   62-77`, `:911-918`: "AO3 History" / "Log in to AO3 to see your reading history." and "AO3
   Subscriptions" / "Log in to AO3 to see the works you subscribe to.", button "Log In to AO3".
   Android `account/AccountWorksListScreen.kt:411-417` and `:1288-1290` show a generic session
   card. Use iOS's per-list card; keep what Android shows for an expired session if iOS
   distinguishes that case (check).
6. **Account header failure.** iOS `Features/Account/AccountView.swift:740` "Couldn't load your
   profile" (with its retry) when the header fails for a reason other than "unavailable";
   Android only handles NotFound (`account/AccountViewModel.kt:154-157`). Add iOS's state.
7. **Screen reader.** (a) Comment avatars: add iOS's hint "Opens author profile"
   (`Features/Comments/CommentThreadRow.swift:1725-1726`). (b) Fandom index empty value "No
   sections" (`Features/Search/FandomListView.swift:303-305`; Android says "No letters
   available", `browse/FandomListChrome.kt:395-405`). (c) A blurred work while selecting: iOS
   says "Hidden mature work", value "Selected"/"Not selected", hint "Double-tap to deselect/select
   this work." (`Features/Privacy/MatureContent.swift:199-203`); Android's
   `hiddenMatureWorkSemantics` (`ui/components/SensitiveWorkRow.kt:78-80`) clears the selection
   state. Fix it in that shared modifier for every caller (rows, ledger rows, covers). (d) The
   tag chip's custom action "Cycle tag" (`TagSelectField.swift:418`; Android
   `search/FilterTagPicker.kt:218-219`). (e) Browse's "+N more" chip says "{N, grouped} more
   fandoms" (`Features/Search/MediaBrowserView.swift:942`; Android
   `browse/BrowseCategoryPanels.kt:300`). (f) "Continue thread, 1 deeper reply / N deeper
   replies" as the spoken label (`Features/Comments/CommentThreadRow.swift:856`, `:876`; Android
   `comments/CommentThreadComponents.kt:382-400`). (g) The account works filter button's label
   "Works Filters" where iOS uses it (`Features/Account/AccountInboxViews.swift:108`), if the same
   control exists on Android; say if not.

Not to change: the comments "kept copy" line after a network failure (Android shows its age
after any failure; that is deliberate). Tests: one per behaviour (2, 3, 4, 5, 6, 7c, and one for
the new shortcut reading an old saved list); structural Compose or JVM tests only (no
`captureToImage`). Existing tests that pin the old behaviour change with the fix; say which.
