TASK: Extend the DEBUG offline review harness to AO3 collections and challenges.
Background: kudos-ao3-reader/App/DemoLibrary.swift `DemoNetworkBlock` answers archiveofourown.org requests from KudosTests/Fixtures/*.html by URL-path pattern (`routes`) when launched with -KudosDemoLibrary YES -KudosFixtureDir <dir>. Collections and challenges have no fixtures yet.
Do: (1) From the inline HTML already in KudosTests/AO3CollectionParsingTests.swift, AO3CollectionItemsScopeTests.swift, AO3ChallengeParsingTests.swift, AO3ChallengeFormTests.swift, build complete page fixtures (collections index for a user, one collection's works, collection items manage page, challenge sign-ups, one sign-up, assignments, prompt meme, challenge settings form, tag set) as KudosTests/Fixtures/ao3_*.html — each must parse with the app's existing parsers (add a small test per fixture asserting the parser returns non-empty results). (2) Add matching `routes` entries in DemoNetworkBlock (more specific patterns before general ones). (3) Add DEBUG routes so these screens can be opened directly at launch, following the existing `acct:` pattern (DebugLaunchRoute in DemoLibrary.swift, AccountView debug .task): e.g. `acct:ao3collections`, `ao3collection:<slug>`, `challenge:<slug>:<screen>`. Everything behind #if DEBUG. Never contact AO3.

ALSO (L3-FORM-1): each of these screens renders its form rows ~52pt tall because the List's minimum row
height inflates them: CollectionModerationView, CollectionMaintainersView, ChallengeSignUpsView,
ChallengeSettingsView, ChallengeSettingsEditSections' host, NewCollectionSheet, AO3CollectionDetailView.
The fix applied elsewhere (WorkEditView, SettingsHubView, EditTagsView): add
`.environment(\.defaultMinListRowHeight, 0)` right after `.cardList()`, and give every section header
row an explicit `.padding(.bottom, 8)` before its `.pageBodyRow(top: 18, …)` where it has none (the
minimum was supplying that gap). List each screen you changed; Claude screenshots before/after.

ALSO (T-320 pattern) — CHECKED 20:40, NOT NEEDED: these are in-list failure cards under the page header, not bare pages; only the label differed and is now 'Try Again'. Original note: the challenge/collection screens' load-failure states are a bare `Text + Button("Retry")`
with no header or wash (ChallengeSettingsView:485, CollectionModerationView:673, CollectionMaintainersView:413,
PromptMemeView:418, ChallengeAssignmentsView:553, ChallengeSignUpsView:402, ChallengeSignUpView:577,
ChallengeSettingsEditView:647, TagSetView:575). Replace each with the page's own header + a
ContentUnavailableView ("Couldn't load from AO3", message, "Try Again") on the screen's wash — see
`WritingLoaderPage` in Features/Writing/WritingDraftsView.swift for the shape.
And add a `series/\d+/edit` fixture (AO3's series edit form) so `acct:seriesedit` reaches the form.
