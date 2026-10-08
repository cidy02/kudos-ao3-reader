# Audit A6: both apps in four themes and at the largest text size (Claude)

Run on `emulator-5556` in airplane mode with the demo library, signed in. Screenshots are
contact sheets in `~/kudos-tools/out/a6/` (not committed).

## Android, pass 1 (2026-10-08, build `e69da6f3` plus the fixes below)

**Seen in Sepia and OLED** (the screens built since the last theme pass): Drafts, the work
form (posted and draft), the text editor with its recovery sheet, a prompt meme's Prompts,
a tag set, AO3 Collections, Reading History. **No fault.**

**Seen at font scale 2.0 in Dark** (21 screens): Home, Library, Browse, Search, Account,
Settings, Queues, Collections, Recently Deleted, Favorites, Inbox, AO3 Preferences, More on
AO3, Drafts, the work form (posted and draft), the editor's recovery sheet, Prompts, a tag
set, AO3 Collections, Reading History.

| # | Severity | Where | What | State |
|---|---|---|---|---|
| 1 | P3 | every section header (`SectionRuleHeader`) | the title wrapped at half the row's width: "READING NOW", "REQUIRED BEFORE POSTING" on two and three lines with room to spare | **fixed**, seen again at 2.0 and at 1.0 |
| 2 | P3 | AO3 Preferences | the Save pill runs off the right edge at 2.0 | open |
| 3 | P3 | Inbox | the filter button's badge is clipped at 2.0 | open |
| 4 | P3 | Settings | a row with no value (Listening) keeps an empty second line at 2.0 | open |
| 5 | P3 | work cards (Favorites) | a "•" separator is left hanging at the end of a wrapped line | open |
| 6 | P3 | Library › Collections | the header is inset further than the cards under it | open |
| 7 | P3 | the editor's recovery sheet | the second copy's date is cut at the edge at 2.0 (check that the row scrolls) | open |

| 8 | **P2** | every Settings action row and other text in the raw accent, Dark and OLED | `#990000` on a near-black panel, about 1.8 to 1: "Export Backup…", "Import Backup…", "Rename" can barely be read. iOS tints the same rows with the same colour. | **owner question 19** |

Also confirmed in this sitting: a quick filter drops hidden rows from a selection (Favorites:
"Delete 1 work?"; a queue: "Remove 3 works from this queue?", audits A5-5 and A5-6); the
keyboard closes when the editor's Done is tapped (brief 3bf's open item).

## Not yet done

- Android: Light at 2.0; Work Detail, the reader and its sheets, comments, an author page,
  Search results and filters, Browse's fandom pages, the collection page and its moderation
  screens, Challenge Settings, the pickers of the work form; every screen at 1.3 (the size
  most large-text readers use).
- iOS: nothing yet. Its four screens never seen offline (comment composer, thread, the
  reader's chrome, Login) and the screens I1 and I2 changed, in four themes and at AX5.
