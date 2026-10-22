# A72: the final side-by-side check, all 65 screens (an index; Claude checks)

**Read-only.** Create `docs/android-port/audits/A72-result.md` FIRST in this worktree; write each
screen's verdict into it as you finish it. Change no other file.

The tiles folders this run gives you hold one PNG per screen (top row iPhone, bottom row Android;
columns Dark, Light, Sepia, OLED, Sepia at the largest text). Both apps were shot tonight on a
fresh demo library, signed in, after every fix from A69, A70 and A71
(`docs/android-port/audits/A70-result.md`, `A70b-result.md`, `A71-result.md` list what was found).

This is the last check before the parity rows are marked done. For **each screen**, give one
verdict: **match** (layout, content, order and theme drawing agree; only fonts, chrome and demo
data differ), **minor** (a difference a careful reader would notice but that loses nothing), or
**differs** (missing or extra information, a different order or layout, a theme drawn wrongly, or
text cut off). For minor and differs, one line each saying what, in which column, and which app.
Also flag **capture problems** (a spinner, a blank or wrong screen, the launcher).

Decided, not to report (owner rules and DECISIONS): Android's navigation and chrome (Material top
bar, back arrow, icon buttons, tab bar, sliders, pager arrows); fonts; demo data (titles, counts,
dates, which works are AO3-linked, reading positions, the books inside the reader); Android's own
extra information (own-works totals, verified author links, affinity tags with their unfold
control, Software Update on About, Backup's notes and Deletion signing, the Font page's imported
font, a History row's favourite star); the Settings hub's stored theme value; iPhone-only cuts at
the largest text (the iPhone's segmented controls stay small; its pinned bars cover rows); the
tab highlighted on Library sections.

Report first the counts (match, minor, differs, capture problems), then "Differs" and "Minor" as
one-line lists, then the per-screen verdicts.
