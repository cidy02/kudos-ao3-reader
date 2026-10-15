# Brief 3fd: A54's six parsing faults

Rules (binding): work only in this worktree (`~/kudos-agent-codex`, branch
`android/agent-codex-3fd`, at the lane's HEAD named in the dispatch); don't commit, push, or
switch branches; never sign in and never contact archiveofourown.org; no stub files; no helper
scripts or `.orig` files left behind; **don't edit `TASKS.md`**. No Room schema or
backup-format change. Your sandbox can't run Gradle: Claude builds, tests and commits
afterwards, so make what you write compile by reading the code around it. End with a short
note, `docs/android-port/briefs/3fd-result.md`: what you changed, file by file, what each test
proves, and what you could not check. The networking policy is binding:
`docs/AO3_NETWORKING_POLICY.md` (paced reads only; no reading the reader did not ask for).

Your A54 (`docs/android-port/audits/A54-result.md`, "Missing ones worth fixing first") found
six. Claude checked the first two in the code. Fix each as iOS does
(`/Users/cidy02/kudos-ios-polish/`, read-only), with a test that ports the iOS assertion
(use the iOS fixture where the rule rests on one; Android's test resources may take a copy):

1. **Assignment joins.** `AO3ChallengeSignUpsState` reads only page 1 of each of Complete,
   Open and Defaults, so a recipient matched on a later page shows UNMATCHED. Follow each
   list's pages as iOS does (`assignmentJoinFetchesEveryPageIncludingOpenAssignments`): one
   paced GET per page, within the screen's lifetime, stopping on a failure (which shows the
   existing match error, never a partial "unmatched"). Say how many reads a large exchange now
   costs and whether iOS caps it; if iOS caps it, cap it the same.
2. **Collection totals.** `AO3CollectionParser` turns absent counts into 0 (`?: 0`). Keep them
   unknown (the model is already `Int?`) and draw unknown as iOS does on the collection's page
   (find what iOS shows for a nil count, and every Android place that reads these counts).
3. **Subscription identities.** Keep each byline's account href beside its pseud
   (`readsTitleAndAllBylineAuthors`), as the rest of the app does for authors.
4. **Preview content.** The preview pane must not succeed empty: keep the workskin fallback or
   report it unreadable (`previewExtractsThePreviewPane`).
5. **Deleted reading date.** Parse AO3's "Deleted work, last visited …" wording so the row keeps
   its date (`readsADeletedWorkRow`).
6. **Preferences links.** Capture the account-management web links (Change Password and the
   rest) so the preferences page keeps them (`parsesTogglesSelectsTextAndWebLinks`), if Android's
   preferences screen shows those rows; if it does not, say so and leave it.
