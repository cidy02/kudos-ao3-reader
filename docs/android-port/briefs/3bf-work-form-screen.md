# Brief 3bf: the work form's screen (no Save yet)

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result. Decide questions about demo fixtures, test data, file placement and naming yourself and
list them under "Decided without asking". Stop only for a question about what the app reads
from or sends to AO3, or what it does to the reader's stored data; even then finish everything
the question does not block first, and put every open question in your final summary. Write
`docs/android-port/briefs/3bf-result.md` as you go.

Read first:
- `briefs/3bb-result.md`, `briefs/3bc-result.md` and `briefs/3bd-result.md` **with their
  landing notes**: what is already on Android (the work form as data with its parser, encoder
  and one-GET repository in `network/ao3/writing/`; the recovery store, checkpoint timer and
  AO3's word count; the text editor in `writing/`), and what was corrected on landing (a
  preview or a sheet that draws a whole chapter at once freezes: long lists are lazy; no
  second implementation of anything that exists).
- `docs/WRITING_EDITOR_ARCHITECTURE.md` §0 and §8.7.
- `briefs/3az-result.md` and `briefs/3be-result.md` with their landing notes (how a pushed
  account screen is built and tested here: `statusBars + 76dp` above the header; no invented
  top buttons; no line heights added to shared components; a new file's type names must not
  repeat a name its package already has; a Compose screen test passes
  `parseDispatcher = Dispatchers.Unconfined`; **a row whose only purpose is something not
  built yet shows its value and opens nothing**).

## What is missing

Android can read AO3's work form (3bb) and edit one text field (3bd), and has no screen that
shows a work to its writer. iOS has `Features/Writing/WorkEditView.swift` (artboards 1bo and
1bs) with `WritingFormFields.swift`. This brief is that screen **without anything that writes
to AO3**: it loads a form, shows it, and lets the writer change it in memory.

## Build

Start the result with what iOS has, read from the code: the header, its title and subtitle in
each case (new work, draft, posted work) and the footnote under it; every section in order
with its header in each case; every row with its label, how its value is worded in each case,
whether it is required, and what it opens; every picker and its choices (they come from the
form AO3 served: never a list written into the app); every footnote, word for word; the top
button; every alert and confirmation; what leaving with unsaved changes does; and everything
that reads or writes AO3, in order (Save, Post, Delete, Preview, the tag and publication
refreshes after a pushed screen), so the Save brief has it.

Then build the screen on Android.

- **Loading:** through 3bb's `AO3WorkFormRepository`: one GET of the new-work page or of a
  work's edit page per opening, and nothing else (iOS's extra read of the account's
  collections belongs to the association pickers' brief). Loading, failure, signed-out and
  "AO3 is busy" states with iOS's words. Signed out reads nothing.
- **What can be changed here, in memory only:** the title; rating, archive warnings,
  categories and language, from the choices AO3 served; the text rows (summary, notes, end
  notes, the chapter's title and text, as iOS has them), each opening 3bd's editor with the
  account, target and field iOS passes (quote iOS's values: they are the recovery key, and a
  different key would hide a writer's recovery copy), and taking the text back at each
  checkpoint and on Done as iOS's binding does; and the publication rows (chapter totals and
  "Work is complete", the publication date and its switch, the two visibility switches,
  comment permissions, the work skin, and the anonymous and collection-inbox switches when
  AO3 served them). Every change goes into the `AO3WorkForm` so that
  `form.parameters(submit)` is what iOS would send after the same taps: that is what the tests
  check.
- **Rows that wait for their own briefs** show the value iOS shows and open nothing: fandoms,
  relationships, characters and additional tags (the tags editor); series, collections, gift
  recipients, co-creators and "Inspired by" (the association pickers); Chapters, Add chapter
  and Edit tags. List each in the result with what iOS opens there.
- **Nothing that writes:** no Save, no Post panel's actions, no Delete, no "Preview on AO3".
  Where iOS draws a control whose only purpose is one of those, leave it out, add no sentence
  in its place, and list it. A footnote that promises one of them is left out too.
- **Nothing in the app opens this screen yet.** Demo routes only (below). A tap on a draft
  and New Work keep opening the browser: do not touch `WritingWorkDestination` or the drafts
  screen. The Save brief will connect them.
- **Leaving:** as iOS does it when nothing can be saved here: say what iOS does with unsaved
  changes and do the part of it that does not need Save.

## How it must be drawn

Layout, content, order and words are iOS's. The subject header, section headers, form rows,
panels and separators already in `ui/subject/` and `settings/` (see how
`account/AO3ChallengeSettingsScreen.kt` and the AO3 collection form in `account/` use them,
including the collection form's text field row); the app's own pickers and switches as those
screens draw them. The palette is `tokens.scopePalette`. The top row's buttons are the app's
Material icon buttons. Tokens only: no stock Material chips, cards, text-field decoration or
default Material colours. Light, Dark, Sepia and OLED; every new text with a line height;
nothing clipped at `isAccessibilityFontScale()`; a pushed screen leaves `statusBars + 76dp`
above its header; long lists are lazy.

## Demo and tests

- Demo routes for the three forms 3bb's demo already answers: a new work, the draft 995001
  and the posted work 995006. Say the three `nav:` routes. A route with an `&` in it is cut
  off by the device's shell: use one argument per route.
- Tests, none reaching the network: each of the three forms shows iOS's sections and rows
  with the right values; each kind of change made through the screen's own state (a title, a
  single choice, a multiple choice, a switch, the date, a text handed back by the editor)
  changes exactly the fields iOS's encoder would change and leaves every other field of the
  untouched round trip as it was; one GET per opening and none after it; signed out reads
  nothing; nothing is sent (a client whose POST throws); the rows that wait open nothing; the
  drafts screen's destinations are unchanged. Compose tests here need a tall window for lazy
  lists, patient waits, and `@GraphicsMode(NATIVE)` when they ask about text.
