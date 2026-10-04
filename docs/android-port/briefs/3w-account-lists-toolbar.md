# Brief 3w: the account lists' toolbar and mature handling, as iOS has them

Rules (binding): work only in this worktree; don't commit, push, or switch branches; never sign in
and never contact archiveofourown.org; no stub files; no helper scripts or `.orig` files left
behind; don't change Room schemas or backup formats; don't edit `TASKS.md`. Your sandbox can't run
Gradle; Claude builds and tests afterwards, so make it compile by reading the real symbols you use.

The screen is `android/app/src/main/java/io/github/cidy02/kudos/account/AccountWorksListScreen.kt`
(Marked for Later, Bookmarks, History, Subscriptions), with `AccountListViewModel` in
`account/AccountViewModel.kt` and its one call in `app/AppNavHost.kt`. iOS's same screen is
`kudos-ao3-reader/Features/Bookmarks/AO3AccountWorksList.swift` (the iOS lane is
`/Users/cidy02/kudos-ios-polish`). iOS wins: same behaviour, iOS's strings verbatim.

## 1. Mature works (do this first, and completely)

Today the ⋮ menu's "Hide Mature Content" / "Show Mature Content" flips a local `hideMature` that
nothing reads, and no row on this screen is ever blurred.

- **The menu item.** Replace it with iOS's `MatureRevealToggle`
  (`Features/Privacy/MatureContent.swift`): "Show mature" / "Hide mature" with the eye icon, present
  only while the `hideMatureContent` setting is on, toggling the shared session `PrivacyGate`.
  `account/AO3CollectionDetailScreen.kt` already does exactly this; copy it, including how it gets
  `SettingsRepository` and `PrivacyGate`.
- **The rows.** Read iOS's `visibleEntries` (about lines 253–262) and how its paired local row
  blurs. Match it:
  - a row paired with a work in the reader's library, rated Mature or Explicit, is blurred in Blur
    mode until revealed (one tap reveals that work; Show mature reveals all). Use
    `SensitiveWorkRow`'s `obscured` and `onReveal`, and decide with
    `library/LibraryPrivacy.visibility(work, privacy, reveal)`, as `library/CollectionDetailScreen.kt`
    does;
  - in Hide mode iOS does not pair a hidden work, so it stays a plain remote row with no local
    state. Do the same where Android builds its pairs (`CanonicalWorkMerge.remoteLed` in the view
    model);
  - a plain remote row (not in the library) is never blurred or hidden on iOS. Keep that.

## 2. The rest of iOS's toolbar (then this, item by item)

iOS's `.toolbar` block (about lines 279–320) has, in order: the Filter button and its panel, then a
menu holding the mature toggle, the display mode picker (not on Marked for Later or
Subscriptions), Expand All (only when the display mode isn't compact), Mark All as Seen (when the
list tracks new chapters and some rows have them), and Clear History (History only, destructive,
with iOS's confirmation). Android has only Expand All.

For each missing item, read what backs it on iOS and look for the same on Android (`ui/subject`'s
`FilterButton`, `search/SearchFilterSheet.kt`, the settings repository, the account repository):

- if Android already has the state or repository call, wire the item up as iOS does, with iOS's
  strings and the conditions under which iOS shows it;
- if it would need an AO3 request Android has no repository call for, or a setting Android doesn't
  have, don't invent one. Leave the item out and say so in the result, with what it would need.

Read `docs/AO3_NETWORKING_POLICY.md` before touching anything that sends a request. Keep every
string and callback the screen has today, apart from the two dead menu labels.

## Result

Write `docs/android-port/briefs/3w-result.md`: what you changed; every new or changed user-visible
string; every signature change; for each iOS toolbar item, whether it is now on Android, and if
not, exactly what is missing; and how each of the four lists treats a Mature work in Blur mode and
in Hide mode, paired and unpaired.
