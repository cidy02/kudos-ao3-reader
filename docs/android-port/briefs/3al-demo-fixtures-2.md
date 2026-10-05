# Brief 3al: demo fixtures for four more things that cannot be seen on the emulator

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; **don't edit `TASKS.md`**. Don't change the backup format or a Room schema. Your sandbox
can't run Gradle or Xcode. Claude builds, tests and commits afterwards, so make what you write
compile by reading the real symbols you use, and say which claims need a test run.

**Android only, and demo data only**, exactly as in brief 3aj (read `briefs/3aj-result.md`
first: it is how the last three fixtures were added, tested and reached). Nothing here may
change what the app does outside the demo. The demo never reaches AO3:
`network/ao3/DemoNetwork.kt` maps AO3 address patterns to fixtures under
`app/src/debug/assets/fixtures/`, and the demo library is seeded by `app/DemoLibrary.kt`. iOS's
demo is the reference for names and numbers (`/Users/cidy02/kudos-ios-polish/`, read-only):
where it already has the thing, use its values. Every fixture is original filler: no copied
prose, nothing taken from AO3.

Write `docs/android-port/briefs/3al-result.md` as you go. For each of the four: which addresses
the screen asks for and which fixture answers each; how to reach it on the emulator in one
line; and one test that fails if the fixture goes missing.

## 1. A series page with works

The series screen (`app/SeriesWorksScreen.kt`, route `series-works/…`) has never been seen with
works: the demo answers no `/series/<id>` address. Give it one series with at least four works
in order (one of them restricted to signed-in readers, one complete, one in progress), its
description and its stats, and make a demo work's series link lead to it.

## 2. An AO3 collection's bookmarks and people

The AO3 collection page (`account/AO3CollectionDetailScreen.kt`) shows works; its Bookmarks and
People tabs (or sections: read the screen) ask for addresses the demo does not answer. Add
fixtures for a collection's bookmarked items and for its maintainers and members, for the
collection the demo already opens.

## 3. A Mature work that is also on an account list

Kudos blurs a Mature or Explicit work's card until it is revealed (the library's privacy
setting). No demo work that is in the library also appears on an AO3 account list, so the blur
has never been seen there. Make one demo library work that is Mature appear on the demo's
Bookmarks or History page with the same AO3 work number, so the account list shows it as a
work already in the library and blurred.

## 4. A subscription to a series and to an author with something new

The Subscriptions page has Works, Series and Authors tabs (`account/AccountWorksListScreen.kt`).
3aj gave Works chapter counts. Give the Series and Authors tabs one entry each that has
something new since it was last seen, if those tabs can show that at all: read the screen and
iOS's, say what each tab can show, and add only what there is a place for.
