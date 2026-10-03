# Brief 3n-inbox: the AO3 Inbox as iOS draws it, keeping every Android action

Work only in this worktree. **Do not commit**, push, switch branches, stash or reset. Leave changes
uncommitted. If your sandbox can't run Gradle, write carefully (declare before use; check that every
symbol and signature exists) and say so. Reading the iOS lane may be slow because of iCloud:
`/Users/cidy02/Documents/AO3_App_OpenSource/.claude/worktrees/handoff-documentation-2151af/.claude/worktrees/polish`.
The demo serves AO3 from fixtures; never contact archiveofourown.org, and never send a write except
against the fixtures.

Rebuild `account/AccountInboxPane.kt` (and its ViewModel only where needed) as iOS's
`Features/Account/AccountInboxScreen.swift` and `AccountInboxFilterSheet.swift` draw it:
- floating pushed chrome;
- `SubjectHeaderBlock` with iOS's kicker, title and count line;
- the scope wash;
- comment rows styled as iOS's;
- the filter sheet with iOS's options and strings.

**Keep every action Android has today.** Paging (Previous / Next and `onLoadPage`), selection mode
(`onBeginSelection`, `onEndSelection`, `onToggleSelectAll`), and the bulk actions mark read, mark
unread and delete (`onBulkMarkRead`, `onBulkMarkUnread`, `onBulkDelete`) must all remain. A first
attempt dropped them and was rejected. Before finishing, diff the strings and `on…` callbacks against
`git show HEAD:<file>`; nothing may disappear unless iOS dropped it (cite the iOS file:line).

Don't touch `backup/`, migrations, `library/`, `settings/`, `account/AO3Collection*` or
`app/MainScaffold.kt`. Write `docs/android-port/briefs/3n-inbox-result.md`.
