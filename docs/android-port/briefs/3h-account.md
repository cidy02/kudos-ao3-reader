# Brief 3h: the Account hub, redesigned as iOS draws it (artboards 1m, 1bt, 1n)

Edit-only. **Do not commit**, push, switch branches, stash or reset. No network. Write code that
compiles by careful reading: declare every value before use, and check every symbol you call
exists with that exact signature, including properties of domain classes. Claude builds and checks
on the emulator.

## Read first
- `docs/android-port/specs/account.md`: the porting spec, with iOS file:line references.
- `docs/android-port/LIVING-PROMPT.md` §1 and §6. **iOS wins**, and behaviour must be identical across
  platforms.
- iOS: `kudos-ao3-reader/Features/Account/AccountView.swift`, `AccountComponents.swift` (including
  `AccountIconSquare`, T-352), `AccountShortcuts.swift`, and the signed-out preview.
- Patterns in the lane: `ui/subject/*` (`AccentIconSquare`, `SubjectHeaderBlock`, `subjectPanel`,
  `SectionRuleHeader`, `SubjectToggle`, `ToolbarCircleButton`), the shell (`app/MainScaffold.kt`;
  Account has no title bar, and its gear floats top-right and fades on scroll), and `app/PushedShellChrome.kt`.

## Build
Rebuild `account/AccountScreen.kt` as iOS's **single flat page**. Android's Overview / Reading / Writing /
Activity tabs go; iOS has one page.
1. **The profile header**: avatar, kicker "AO3 ACCOUNT", username, "Signed in", the
   "Posting as …" pseud pill and the "…" menu.
2. **Shortcuts**: the 3×2 grid of tiles (`AccountShortcutGridTile`: accent square, count, label), with
   the editor in the section's chevron, as iOS does.
3. **Reading, Writing, Activity, Account**: groups of rows, each row with the 22dp accent square (T-352),
   title, optional subtitle, count and chevron, under collapsible `SectionRuleHeader`s, with the same
   destinations iOS links to (Marked for Later, Bookmarks, Collections, Subscriptions, Works, Series,
   Drafts, History, Inbox, Preferences, More on AO3, and so on). Where Android has no screen yet, keep
   the row and route it to the closest existing Android screen, and list it in the result.
4. **Signed out (1n)**: iOS's preview of the signed-in hub plus the sign-in call to action, with iOS's
   copy.
**Keep every Account action Android has today working** (sign in and out, the inbox, lists, about,
bug report, privacy).

Don't touch `backup/`, `data/local`, migrations, `browse/`, `search/` (another agent is there) or
`works/` (another agent is on Work detail). Write `docs/android-port/briefs/3h-result.md` (under 300 words).
