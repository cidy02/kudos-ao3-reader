# 3n Inbox result

Rebuilt `AccountInboxPane.kt` with the scope wash, `AO3 Account` / `Inbox`
`SubjectHeaderBlock`, iOS tally, All / Unread / Awaiting reply / Replied presets,
joined glass comment rows, selection bubbles, floating filter/more controls, bottom bulk bar,
and an `Inbox Filters` sheet made from AO3's parsed fields/options. The pane registers
`ProvidePushedShellChrome`; `AccountScreen.kt` remains untouched as required. Quick presets apply
their two AO3 filters atomically through the small `AccountInboxViewModel.applyFilters` addition.

## Preservation audit against `git show HEAD:android/app/src/main/java/io/github/cidy02/kudos/account/AccountInboxPane.kt`

Before, visible strings were: Inbox; Loading Inbox; Couldn't load your inbox; Something went wrong.;
Retry; No comments yet; the old “Comments on your works, and replies…” copy; Inbox update; Dismiss;
OK; Filters; Select/Deselect all; Done; Select inbox items; Selected; A comment here is unavailable;
Replied; Open Thread; Mark Read/Unread; Delete From Inbox; Previous/Next; page/count labels; and the
old remove-notification confirmations. After, retained actions/statuses are joined by AO3 Account,
Select, Inbox Filters, All, Unread and Awaiting reply. Intentional replacements match iOS: `Try
Again` and empty copy (`AccountInboxViews.swift:523-549`); update alert (`AccountInboxScreen.swift:114-118`);
filter title (`AccountInboxFilterSheet.swift:61-70`); Select All capitalization
(`UIComponents/WorkBulkActionBar.swift:189-197`); eye-slash unavailable state
(`AccountInboxViews.swift:261-279`); and delete titles/messages (`AccountInboxViews.swift:887-920`).

Required callbacks remain: `onLoadPage`, `onBeginSelection`, `onEndSelection`,
`onToggleSelectAll`, `onBulkMarkRead`, `onBulkMarkUnread`, `onBulkDelete`, `onFilter`, `onSelect`,
`onOpen`, `onToggleSelection`, `onMarkRead`, `onMarkUnread`, and `onDelete`. Checkbox
`onCheckedChange` moved to the whole-row `onToggleSelection`, matching iOS
`selectionContent` (`AccountInboxViews.swift:281-319`).

Verification: `git diff --check` passed. Gradle could not start in this sandbox: its normal home lock
was denied, and a writable offline home then failed when Gradle's file-lock listener tried to bind a
local UDP socket. No emulator screenshot was taken. No AO3 request or write was made.
