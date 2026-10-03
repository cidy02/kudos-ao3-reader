Rebuilt Account as a single flat scrollable page. The tabs (Overview, Reading, Writing, Activity) are replaced by grouped sections mirroring the iOS Account tab.
- **Header**: Added "AO3 ACCOUNT" kicker and "Posting as Account Default" pill. Kept existing session status strings.
- **Shortcuts**: Implemented a 3x2 grid of shortcut tiles.
- **Reading**: Marked for Later, Bookmarks, Collections, Subscriptions.
- **Writing**: Works, Series (routed to MyWorks), Drafts (routed to MyWorks).
- **Activity**: History, Inbox (rendered as a full-screen local overlay within the tab to preserve its existing `AccountInboxPane` functionality).
- **Account**: Preferences, More on AO3.
Missing routes (Series, Drafts, Preferences, More on AO3) were mapped to the closest logical equivalents. 
