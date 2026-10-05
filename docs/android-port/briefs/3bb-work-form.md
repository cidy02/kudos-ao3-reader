# Brief 3bb: Writing foundations 1, AO3's work form (read, model, encode; no screen)

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only.** iOS is the reference: read it at `/Users/cidy02/kudos-ios-polish/`, change
nothing there. **When this brief and iOS's code disagree, iOS's code wins**; say so in the
result, and if a question remains, ask it at once and stop rather than guess (put **every**
open question in your final summary, not only the first). Write
`docs/android-port/briefs/3bb-result.md` as you go.

Read first: `docs/WRITING_EDITOR_ARCHITECTURE.md` §0 to §3 and §12 (the design both platforms
follow; what iOS ships today is its native HTML mode, steps E1 and T-279's part of E2);
`briefs/3az-result.md` with its landing note (the drafts list: where a draft tap goes today);
`briefs/3at-result.md` with its landing note (the collection form: the same kind of work, a
served form parsed, changed and sent back); `docs/AO3_NETWORKING_POLICY.md`.

## Why this brief has no screen

Android has no work editor. Posting a work is the least reversible thing this app can ask AO3
to do: it notifies subscribers and cannot be taken back. So the editor is built from the
bottom, each layer proved before the next. This layer is AO3's work form as data: read it,
hold it, and write it back out **exactly**, with nothing lost. No screen, no route, no button,
and **no request that changes anything on AO3** is added by this brief. The next briefs add
the recovery store, then the editor's screens, then Save, then Post.

## iOS reference

`Models/AO3WritingModels.swift` (`AO3WorkForm` and what it holds), `Services/AO3Client+Works.swift`
(`workFormHTML`, the form parser, `workFormElement`), `Services/AO3WorkActions.swift`
(`saveWork` and every `submit` it takes, `previewWork`, the form's parameter encoder), and the
tests of each under `KudosTests/`.

Start the result with the inventory, read from the code:

1. Every field of AO3's new-work and edit-work form that iOS reads: its form name, its kind
   (text, long text, single choice with its options, multiple choice, checkbox, date parts,
   hidden), and where it lands in `AO3WorkForm`.
2. For each field, how it is written back for each kind of submit iOS has (save as draft, save
   changes to a draft, update a posted work, post, preview): the name, the value, and what an
   empty or unchanged value sends. Include the token, the method override and the submit
   button's own name and value.
3. Every field AO3 serves that iOS **does not read**, and what happens to it on save: sent back
   as served, sent empty, or not sent. **If saving through iOS's encoder would blank or change
   anything the reader did not touch, put it at the top of the result as a data-loss risk**
   (the collection form had one such field).
4. Which page each form is read from, and the reads `saveWork` makes before its one POST.

## Build

- `network/ao3/writing/`: the form's model, its parser (new-work page and edit-work page), and
  its encoder for each kind of submit, as pure code with iOS's field names and iOS's rules.
  Options AO3 serves (ratings, warnings, categories, languages, work skins, the reader's
  pseuds, series, collections) are kept as served, never hard-coded. Anything the parser does
  not understand is kept and sent back as served, not dropped: say how.
- A repository read for the two pages, through the existing authenticated client, taking a
  `parseDispatcher` parameter as `AO3CollectionDetailRepository` does. Nothing calls it yet
  except tests and the demo fixture test.
- **Do not add** a save, post, preview or delete function to `AO3WriteRepository`, a screen, a
  route, or a change to where a draft tap goes. If you find yourself needing one of them to
  finish, stop and say so.

## Demo and tests

- Fixtures (original filler only) under `app/src/debug/assets/fixtures/`: AO3's new-work page
  for the demo account; the edit page of a draft from the drafts fixture (work 995001); the
  edit page of a posted, multi-chapter work in a series and two collections, with a co-creator,
  a gift recipient, an "inspired by" link, a backdated publication date, a work skin, comment
  moderation on, and tags of every kind, some with commas, ampersands, quotes and non-Latin
  characters. Add the two edit pages to the demo network's local answers (reads only), sharing
  an address's existing answer if it has one.
- Tests, none reaching the network. The one that matters most: **parse a served form, encode
  it unchanged, and the encoded fields equal the form's own successful controls** (what a
  browser would send from the untouched page), for each fixture and each kind of submit, field
  by field, with a failure message naming the field. Then: each kind of field changed and
  encoded; iOS's rules for empty values; multiple choices and checkboxes with their hidden
  twins; date parts; unknown fields kept; a page that is a login form, an error page or the
  overload page refused with a typed error; iOS's own test cases for the parser and encoder
  ported as they are, with their names.
