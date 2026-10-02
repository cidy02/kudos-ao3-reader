# Brief 3s: porting specs for Home and Library

You may create or edit only `docs/android-port/specs/home.md` and `docs/android-port/specs/library.md`.
Do not touch code, git or the network.

These specs will be handed to another coding agent that rebuilds each Android screen as the iOS
app draws it. The rule (owner decision): **iOS code is the source of truth**. The design spec
(`docs/design/Final_Redesign_Spec.dc.html`, artboards `<div class="dv-opt" id="1b">` etc.) only
fills in details iOS leaves open. Android's design system already exists in
`android/app/src/main/java/io/github/cidy02/kudos/ui/subject/` (read `docs/android-port/briefs/1a-result.md`
for the iOS → Kotlin names).

For **Home** (iOS `kudos-ao3-reader/Features/Home/`, artboards 1b, 1ad, 1ae, 1af, 1ag) and **Library**
(iOS `kudos-ao3-reader/Features/Library/LibraryView.swift` and its sections, artboards 1c, 1d,
1ah, 1ai, 1aj, 1ak), write one spec each with these sections:

1. **Screen tree.** The top-down structure of the iOS screen: each section, in order, with the
   iOS view or file that draws it, and what it shows when empty, collapsed, or in select mode.
2. **Components.** Each iOS component used (`SubjectHeaderBlock`, `SectionRuleHeader`, cover cards,
   ledger rows, the queue deck card, the resume hero, chips, rings, and so on) with its key sizes,
   paddings, fonts, colours and opacities as the iOS code sets them, and the matching
   `ui/subject` Kotlin component (or "missing: build it").
3. **Data.** Where each section's data comes from on iOS (queries, sort order, limits, filters)
   and the closest Android repository or ViewModel source today
   (`android/app/src/main/java/io/github/cidy02/kudos/home/`, `library/`).
4. **Interactions.** Taps, long-press menus (each item, its label and action), swipe actions,
   See all, select mode and its bulk bar, the toolbar buttons (top right; at most four), and the
   pull-to-refresh behaviour.
5. **Strings.** Every user-visible string verbatim, including empty states and menu labels.
6. **Owner decisions** that shaped the iOS screen (search the iOS code for comments like
   "owner, 2026-" and TASKS.md rows): one line each.
7. **Android gaps.** What Android lacks to draw this, as a short list.

Cite iOS file:line for every non-obvious claim. Don't invent anything: if unsure, write "UNSURE"
and say what would settle it. About 1,500 to 2,500 words each.
