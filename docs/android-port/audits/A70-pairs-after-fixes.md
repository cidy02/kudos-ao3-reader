# A70: the iPhone and Android, screen beside screen, after A69's fixes (an index; Claude checks)

**Read-only.** Change no file except your result. Create `docs/android-port/audits/A70-result.md`
FIRST with an empty "Differences worth fixing" list, then write each screen's findings into it the
moment you finish that screen.

The images are in `/Users/cidy02/kudos-tools/pairs/tiles/` (one PNG per screen). Each
tile has two rows: the **top row is the iPhone**, the **bottom row is Android**; the five columns are
Dark, Light, Sepia, OLED, and Sepia at the largest text size. Both apps run the same demo library,
signed in. Screens whose name starts `s_` are Settings pages.

Owner rules (binding): "Layout, content, order of information and behaviour stay in step with
iOS. Navigation and chrome controls are Android's own" (a Material back arrow, Material top bar
and icon buttons, the tab bar's look); "the goal is visual and UX parity with no lost features or
information". So report:

- **missing or extra information**: a row, figure, count, label, line of text, control or
  section one app shows and the other does not;
- **order**: sections or rows in a different order;
- **layout**: a different grouping, card or panel shape, alignment, or size that a reader would
  notice (not pixel nudges);
- **theme**: a wash, background, card or accent colour that differs in one theme; text that is
  hard to read; Sepia or OLED drawn like another theme;
- **largest text**: text cut off, overlapping, truncated with "…" where the other app wraps, or a
  control pushed off screen.

Ignore: the status bar, the top bar and back button style, the tab bar's look, fonts (San
Francisco vs Roboto), and demo data that differs because of time (dates, "x minutes ago").

## Report
First "Differences worth fixing": one line each, screen + theme column + what differs + which
app differs from the other, most noticeable first. Then, per screen, a short list (or "the same").
Say "unsure" when an image is too small to tell, rather than guessing.

## What is new since A69

Android was rebuilt with A69's fixes (brief 3gg) and shot again on a fresh demo library. A69's
result is `docs/android-port/audits/A69-result.md`. For each screen, say whether each A69 item
for it is **gone**, **still there** or **changed**, then list anything new.

**Decided; do not report again unless it changed:**
- Drafts' expiry pills, "Created" footers and "expiring this week" line (iOS draws them too; the
  iPhone's demo has other drafts).
- Subscriptions' "New since you last looked" / "All works" sections, stats lines, chapter ranges
  and Unsubscribe (iOS has them; the iPhone's demo data is sparser).
- Android's extra Backup notes and Deletion signing section, Settings › Font's imported "Demo font"
  row, and Android's paired "Demo reading tablet": demo data or owner questions still open.
- Demo data that differs (titles, counts, which works are in which list, dates), the status bar,
  top bar and back button style, the tab bar's look, fonts, and a pager's arrow style.
