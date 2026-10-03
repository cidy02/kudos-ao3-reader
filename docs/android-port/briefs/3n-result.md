# 3n result (written by Claude; Gemini Flash stopped at a ~69 h quota)

Landed: `account/AccountWorksListScreen.kt` replaces `AccountListScreen` for Marked for Later,
Bookmarks, History and Subscriptions:
- the subject header with a count;
- per-list chips (e.g. All / Updated / Downloaded);
- full `SensitiveWorkRow` cards with the privacy blur;
- Unmark / Unsubscribe actions;
- paging, and iOS's footnotes.

Supporting models: `AO3ReadingEntry`, `SubscriptionWatermarks`, plus parser fields.

The old list's row actions (queue, collection, favourite, download…) were empty no-ops, so nothing
real was lost.

**Not landed:** Flash's Inbox rework. It was mid-edit and dropped paging, selection mode and bulk
mark-read, mark-unread and delete. Kept aside at `scratchpad/AccountInboxFilterSheet.kt.3n`, and its
diff is in Flash's worktree. Inbox still needs its redesign (brief 3n-inbox).

Follow-ups:
- the ⋮ on these lists should be a glass circle (`ToolbarCircleButton`);
- check each list against iOS.
