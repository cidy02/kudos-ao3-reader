# A71: the iPhone and Android, the second batch of screens (an index; Claude checks)

**Read-only.** Create `docs/android-port/audits/A71-result.md` FIRST in this worktree with an empty
"Differences worth fixing" list; write each screen's findings into it as you finish it. Change no
other file.

The tiles are in the folder this run gives you (one PNG per screen, 29 screens). Each tile has two
rows: the **top row is the iPhone**, the **bottom row is Android**; the columns are Dark, Light,
Sepia, OLED, and Sepia at the largest text size. Both apps run a fresh demo library, signed in,
with AO3 answered from the same test pages.

The screens: a saved work's page (`workdetail`) and its My copy sheet (`mycopy`), the reader
(`reader`), a work's comments (`comments`), another reader's AO3 profile (`author`), the account's
series (`myseries`), the work form for a posted work and for a draft (`workedit`, `draftedit`), a
collection's Challenge Settings, Sign-ups, Assignments, Your Sign-up, Prompts, Maintainers,
Moderation and Collection Settings (`chsettings`, `chsignups`, `chassign`, `chmysignup`,
`chprompts`, `colmaint`, `colmod`, `colsettings`), first-run Welcome, the sync-folder setup and
What's New (`welcome`, `synconb`, `whatsnew`), six Library sections (`sec_*`), two Home sections
(`hsec_*`), a reading queue (`queue`) and a collection (`collection`).

Owner rules (binding): layout, content, order of information and behaviour stay in step with iOS;
navigation and chrome controls are Android's own (Material back arrow, top bar, icon buttons, the
tab bar's look, a slider's track, a pager's arrows); "visual and UX parity with no lost features
or information". Where Android shows information the iPhone does not, say so; it is kept.

Report:
- **missing or extra information** (a row, figure, count, label, line, control or section);
- **order** (sections or rows in a different order);
- **layout** (grouping, card or panel shape, alignment, size a reader would notice);
- **theme** (a wash, background, card or accent colour that differs in one theme; text hard to
  read; Sepia or OLED drawn like another theme);
- **largest text** (cut off, overlapping, truncated where the other wraps, a control pushed off);
- **capture problems** (a column showing a loading spinner, a different screen, or the app's
  launcher): name them, they are retaken, not fixed.

Ignore: the status bar, fonts (San Francisco vs Roboto), demo data that differs by time (dates,
"x minutes ago") or by a reading position, and the book's text inside the reader (each app opens
its own demo book).

First "Differences worth fixing": one line each, screen + column + what differs + which app,
most noticeable first. Then, per screen, a short list (or "the same"). Say "unsure" when an image
is too small to tell.
