# A76: the last side-by-side check, all 67 screens (an index; Claude checks)

**Read-only.** Create `docs/android-port/audits/A76-result.md` FIRST in this worktree; write each
screen's verdict into it as you finish it. Change no other file.

The tiles folder this run gives you holds one PNG per screen (top row iPhone, bottom row Android;
columns Dark, Light, Sepia, OLED, Sepia at the largest text: iPhone AX5, Android font scale 2.0,
which is the smaller of the two). Android was shot today on a fresh demo library, signed in, after
every fix from A72 (`docs/android-port/audits/A72-result.md`, with its triage at the foot: read it
first). Two screens are new: `compose` (the comment composer) and `bugreport` (Report a Bug).

This is the check before the parity rows are marked done. For **each screen**, give one verdict:
**match** (layout, content, order and theme drawing agree; only fonts, chrome and demo data
differ), **minor** (a difference a careful reader would notice but that loses nothing), or
**differs** (missing or extra information, a different order or layout, a theme drawn wrongly, or
text cut off or ending in "…" on one side only). For minor and differs, one line each saying what,
in which column, and which app. Also flag **capture problems** (a spinner, a blank, wrong or
half-drawn screen, a system dialog, the launcher).

Decided, not to report (owner rules, DECISIONS and A72's triage): Android's navigation and chrome
(Material top bar, back arrow, icon buttons, tab bar, sliders, checkboxes, overflow ⋮ menus);
fonts; the two apps' demo data (titles, counts, dates, which works are listed, reading positions,
completion, the books in the reader, Android's extra demo bookmark); Android's own extra
information (own-works totals, verified author links, affinity tags with their unfold control,
Software Update on About, Backup's notes and Deletion signing, the Font page's footer and imported
font, a History row's favourite star); Android's System theme option; the Welcome icon art; the
sync setup's checkbox (iOS: a switch); the paged assignments list's Load more; the default user
icon; the iPhone's account Works subtitle showing only the name; the Settings hub's stored theme
value; the tab highlighted on Library sections; the iPhone's larger largest size (compare what is
on screen, not how much fits); a frame that ends before a list's last group.

Report first the counts (match, minor, differs, capture problems), then "Differs" and "Minor" as
one-line lists, then the per-screen verdicts.
