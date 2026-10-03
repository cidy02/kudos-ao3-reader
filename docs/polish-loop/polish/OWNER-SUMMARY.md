# Polish loop — owner summary

The loop (LOOP-v3) audited every iPhone screen against the redesign spec, in two passes, and fixed what didn't
match. Everything is on `integrate/cloud-redesign` (latest `90ca7ca2`). Nothing has been
pushed since the backup push you asked for, and nothing was merged to `main`.

## Where it stands

- **Inventory:** all 68 iPhone screens and sheets were audited in the first pass. The second pass re-checked them in
  Dark, Light, Sepia and OLED and at the largest accessibility text size (AX5).
- **Tests:** full suite on integrate, 2,281 tests. The only failures are the known environment failures: the 10
  backup/sync case-folding tests and the Kokoro names test. The queue-notes round trip passed this time.
- **Lint:** 0 errors, 123 warnings (it was 125 when the loop started).
- **Open issues:** no open P1 or P2. The remaining P3s are listed at the end.
- **Your phone:** "Yan's iPhone" has `baec039b`. It does not yet have the Browse results redesign, the fandom A–Z index
  or the last two batches. Ask and I'll install the latest.

## What changed, by area

**Whole app**
- **Form rows (Settings, AO3 Preferences, challenge and collection forms):**
  - Rows sit at their own ~42pt height instead of the List's ~52pt minimum.
  - Values no longer truncate next to short labels.
  - Rows scale with Dynamic Type; at accessibility sizes the value moves under its label, as iOS Settings does.
- **Filled buttons:** labels are readable on every theme (black or white, picked by contrast).
- **Teen rating:** the yellow "T" is now legible in Light and Sepia.
- **Accent colour:** accented controls take the colour of the screen they're on; no stray app-red.
- **Failed loads:** they keep their page header and say "Try Again".
- **Large text:** one-word titles and usernames shrink instead of splitting mid-word, and chips never wrap inside their capsule.

**Library and Home**
- **Library:** collection cards, the queue pages and details, and the filter panel match the spec; the shelf shadows are fixed.
- **Your copy of a work:** the "My copy" sheet now matches its artboard (1a).
- **Home:** Recently Updated pills, and the resume card at large text sizes.
- **New collection:** explains what happens when you pick no colour.

**Browse and Search**
- **Browse → category → fandom results** (your request) now use the Search tab's redesigned page.
- **Fandom list:** A–Z scrub index, stars on favourite fandoms, downloaded counts, and simpler family cards.
- **Save Search:** a part-height sheet whose summary shows included, excluded and other filters in distinct styles.

**Account and AO3**
- **Account hub, Dashboard, Inbox, Bookmarks, Subscriptions and AO3 Preferences** match their artboards.
- **Author pages:** the Ledger/Detailed picker works now (it did nothing before).
- **Settings:** pages no longer repeat their own title as a section header.

**Challenges and AO3 collections**
- **Layouts:** Moderation, Maintainers, Assignments, Prompt Meme, Tag set, Challenge settings and Collection items
  follow their artboards (1by–1ch, 1s).
- **Fixed:** two rows that did nothing when tapped ("Recently decided" and Prompt Meme's "Prompts").

**Reader, writing and utilities**
- **Comments:** the formatting bar and the thread screen header.
- **Chapter editor:** the toolbar matches 1bv.
- **Privacy and local data:** mint panel; sizes read "0 bytes", not "Zero KB".
- **Availability check:** a proper list, with Done on the right.
- **Read Aloud sheet:** follows the theme.

Full detail: `TASKS.md` rows T-287 to T-334, and `.claude-overnight/polish/STATUS.md` / `FINDINGS.md`.

## What to try first

1. Browse → a category → a fandom (Search-style results), and the fandom list's A–Z index.
2. Settings → Display & Text Size → largest size, then open Settings, AO3 Preferences and Account.
3. Switch to Light and to Sepia and open any work list (the Teen rating, filled buttons).
4. An author page → "…" → Detailed.

## Your decisions

`OWNER-DECISIONS.md` has 10 items, each with options and my recommendation. The ones that matter most:
- **#2 and #8:** sheet and form confirm controls. Choose text buttons or the spec's check circles, one convention for the whole app.
- **#4:** whether Hide Mature also blurs adult works on AO3 lists. I recommend yes.
- **#10:** whether History opens as a list, as 1t draws it, rather than the cover grid. I recommend yes.

## Known limits and open P3s

- **Not screenshotted offline,** so code-reviewed only: the comment composer, the thread screen, reader chrome, and
  Login (its web view could reach AO3).
- **Tag set counts** read 0 in the offline fixture; check them against a real tag set.
- **Small P3s:** the Add Works sheet title truncates; text-field form rows squeeze their value at AX5; about 15
  Library and Work Detail row titles are still fixed-size (they don't grow with Dynamic Type — a batch like T-334
  would cover them).
- **Grok** stayed out of credit; **agy's Opus 4.6** is out of quota for about six days. Codex, Gemini Flash and Claude did the rest.
- **iCloud:** the repo lives in iCloud-synced Documents with Optimize Storage on, so iCloud kept evicting source and
  `.git` files and stalling builds. I freed ~40 GB of stale build caches with your OK. Turning off Optimize Storage for
  this folder, or moving the repo, would stop it.
