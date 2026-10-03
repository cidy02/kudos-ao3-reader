## 1. iOS View Breakdown
- Header: Kicker ("Collection"), Title, Subtitle (Byline and Summary)
- Stats: Works count, Bookmarks count
- Segments:
  - Works (Empty state, "Recent" section, Work rows with ANON badge)
  - Bookmarks (Empty state, "Recent" section, Work rows with ANON badge)
  - People (Empty state, "People" section, Person rows)
- Manage Actions:
  - Maintainers
  - Moderation
  - Collection Settings
  - Sign-ups
  - Assignments
  - Prompts
  - Your Sign-up
  - Challenge Settings

## 4. Unported Actions (Web Fallback)
The following actions write to AO3 and do not have native write paths implemented yet in Android, so they will use the web fallback:
- Collection Settings (Edit)
- Challenge Settings (Edit)
- Maintainers (Edit)
- Moderation (Edit)
- Sign-ups / Assignments / Prompts / Your Sign-up
