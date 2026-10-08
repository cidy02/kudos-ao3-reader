# A15: Android String Check

1. **Counts:**
   - iOS files read: 22
   - Strings checked: 435
   - Found: 415
   - Not found: 20

## Not found on Android

| String | iOS File | Kind | Search Run | Nearest Android File |
|---|---|---|---|---|
| `1 needs a decision` | `AO3CollectionScreenDecisions.swift:76` | String Literal | `grep -rlF "1 needs a decision" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionModerationScreen.kt` |
| ` need a decision` | `AO3CollectionScreenDecisions.swift:77` | String Literal | `grep -rlF " need a decision" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionModerationScreen.kt` |
| `These are your AO3 collections. Collections you make in Kudos are in Library.` | `AO3CollectionsList.swift:382` | Text | `grep -rlF "These are your AO3 collections. Collections you make in Kudos are in Library." android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3CollectionsScreen.kt` |
| `AO3 matches participants. In Kudos, you can view sign-ups and assignments and ask for ` | `ChallengeSettingsView.swift:439` | Text | `grep -rlF "AO3 matches participants. In Kudos, you can view sign-ups and assignments and ask for " android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsScreen.kt` |
| `None sent yet` | `ChallengeSettingsView.swift:595` | String Literal | `grep -rlF "None sent yet" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3ChallengeSettingsScreen.kt` |
| `New prompt` | `PromptMemeView.swift:160` | Text | `grep -rlF "New prompt" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3PromptMemeScreen.kt` |
| `Fandoms per person` | `TagSetView.swift:372` | String Literal | `grep -rlF "Fandoms per person" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3TagSetScreen.kt` |
| `Characters per person` | `TagSetView.swift:379` | String Literal | `grep -rlF "Characters per person" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3TagSetScreen.kt` |
| `Relationships per person` | `TagSetView.swift:386` | String Literal | `grep -rlF "Relationships per person" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3TagSetScreen.kt` |
| `Additional tags per person` | `TagSetView.swift:393` | String Literal | `grep -rlF "Additional tags per person" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/AO3TagSetScreen.kt` |
| `Reload tags` | `WorkEditView.swift:78` | Button | `grep -rlF "Reload tags" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt` |
| `Reload chapter totals` | `WorkEditView.swift:117` | Button | `grep -rlF "Reload chapter totals" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt` |
| `Fill in what is missing` | `WorkEditView.swift:214` | Button | `grep -rlF "Fill in what is missing" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt` |
| `. AO3 requires ` | `WorkEditView.swift:770` | String Literal | `grep -rlF ". AO3 requires " android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt` |
| `Edit chapter` | `WritingDraftsView.swift:483` | String Literal | `grep -rlF "Edit chapter" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/account/WritingDraftsScreen.kt` |

## Found, but worded differently on Android

- iOS string: `"AO3 deletes an unposted draft 30 days after you create it. Recovery copies stay on this device and aren't deleted with it."` (`kudos-ao3-reader/Features/Writing/WritingDraftsView.swift:142`)
- Android string: `"AO3 deletes an unposted draft 30 days after you create it."` (`android/app/src/main/java/io/github/cidy02/kudos/account/WritingDraftsScreen.kt:338`)

## Expected: write not built

| String | iOS File | Kind | Search Run | Nearest Android File |
|---|---|---|---|---|
| `Post work` | `WorkEditView.swift:212` | Button | `grep -rlF "Post work" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt` |
| `Delete work on AO3` | `WorkEditView.swift:521` | String Literal | `grep -rlF "Delete work on AO3" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingWorkFormScreen.kt` |
| `This will delete all comments on the chapter as well and cannot be undone.` | `WritingTextEditor.swift:146` | Text | `grep -rlF "This will delete all comments on the chapter as well and cannot be undone." android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingTextEditorScreen.kt` |
| `Preview on AO3` | `WritingTextEditor.swift:190` | Button | `grep -rlF "Preview on AO3" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingTextEditorScreen.kt` |
| `Delete chapter` | `WritingTextEditor.swift:194` | Button | `grep -rlF "Delete chapter" android/app/src/main/` | `android/app/src/main/java/io/github/cidy02/kudos/writing/WritingTextEditorScreen.kt` |

## What I did not read

- Files outside `Features/Challenges/`, `Features/Writing/` and `Features/Account/AO3Collection*.swift`
- Android files outside `android/app/src/main/`
- Comments, `#Preview` blocks, debug-only code (`#if DEBUG`), or log messages.

## Triage (Claude, 2026-10-08)

Nothing missing beyond the writes not built yet ("New prompt", "Reload tags", "Reload chapter
totals", "Fill in what is missing", "Edit chapter"). "Fandoms per person" and its three
siblings are on the screen (built from a pattern, so the exact search missed them). Left as
P3 wording: the collections list's footnote, Challenge Settings' "None sent yet" and its
note on matching, Moderation's "N need a decision".
