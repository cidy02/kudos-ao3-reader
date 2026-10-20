# Brief 3fu: own Works and Series, a card's unfold control, lists that open on Compact (owner Q24/Q25, 2026-10-20)

**Write code; do not commit, push, switch branches, sign in, run Gradle or contact
archiveofourown.org.** Claude builds, tests and lands it. Do not edit `TASKS.md`. Leave a result
file, `docs/android-port/briefs/3fu-result.md`, written as you go: what changed (`path:line`), the
iOS code each change follows (`path:line`), tests added, what you could not do.

Hard rules: iOS is the source of truth; nothing Android shows today may be lost (owner,
2026-10-20: "the goal is visual and UX parity with no lost features or information"); Android's
own navigation and chrome (Material 3 top bar and icon buttons) stay. No Room or backup change.

The owner answered on 2026-10-20: match the iPhone on all three.

1. **Own Works and own Series (Q24).** iOS shows the signed-in writer's own Works and Series as a
   plain list under the writer's name, with a row of fandom chips on Works
   (`Features/Authors/AuthorProfileView.swift` own-account path, `OwnWorksBulkBar.swift`; find
   where iOS routes Account › Works and Account › Series). Android keeps the profile's four tabs
   (Works, Series, Bookmarks, About) and the writer's totals under the title
   (`author/AuthorProfileScreen.kt`, the `ownAccount`/dashboard paths; 3ch's totals line
   "12 works · 248,400 words · 3,812 kudos"). Make Android's own pages iOS's shape. **Keep the
   totals line** (owner: no information lost) and keep every action the own pages have today
   (Select, Edit multiple works, row menus, "+", Load More). Bookmarks and About stay reachable
   the way iOS reaches them from the Account hub.
2. **A card's unfold control (Q25a).** On iOS it sits at the card's foot
   (`Features/Library/WorkRow.swift` around `:303`–`:351`, `isExpanded`, the chevron); on Android
   before the title (find it: `ui/components/SensitiveWorkRow.kt` and the AO3 card). Move it to
   the foot on every card that has one; same rule for when it shows (a long summary or tags).
3. **Lists open on Compact (Q25b).** iOS: `@AppStorage("account.displayMode") … = .compact`
   (`Features/Account/AccountView.swift:49`, `Features/Bookmarks/AO3AccountWorksList.swift:166`).
   Android's `account/AccountWorksListScreen.kt:168` already defaults to Compact; check History,
   Bookmarks and every other works list that iOS opens on Compact and make each Android default
   match (a stored choice the reader already made stays).
4. Tests: a Compose or JVM test per item where the rule is testable (the default layout, the
   own-works shape keeping the totals line, the unfold control's position via semantics order).
