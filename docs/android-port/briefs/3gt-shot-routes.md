# Brief 3gt (Android): a debug route for each screen still to be shot

**Write code in this worktree only (`/Users/cidy02/kudos-agent-codex`, branch
`android/agent-codex-shots`). Do not commit, push, switch branches, sign in, contact
archiveofourown.org, or run Gradle (Claude builds and tests).** Do not edit `TASKS.md`. Create
`docs/android-port/briefs/3gt-result.md` FIRST and fill it in as you go.

The side-by-side passes shoot each screen on both phones by launching the app once with a debug
extra (`adb shell am start -n io.github.cidy02.kudos/.MainActivity --es kudosDebugRoute nav:<route>`;
find where `MainActivity` reads `kudosDebugRoute` and opens `nav:` routes; the demo library is
seeded by `app/DemoLibrary.kt`). `docs/android-port/audits/A82-shots.md` names 70 screens never
shot (from Grok's inventory, `audits/A81-result.md`, which has each screen's file and how the demo
reaches it by hand).

For each name in A82, make `--es kudosDebugRoute shot:<name>` open the app on exactly that screen
with the demo library: its page, with its sheet, dialog or picker open on top where the screen is
one of those.

1. **DEBUG only**, behind `BuildConfig.DEBUG` like the existing debug routes; a release build
   behaves exactly as now. A route makes no network request beyond what opening the same screen by
   hand makes (the demo's fixtures).
2. **One small mechanism:** one dispatcher (a `when (name)`) that opens the page (the existing
   `nav:` routes) and then asks that page to open its sheet. A page reads a pending request once
   (for example a small debug holder consumed in a `LaunchedEffect`); with no request pending,
   nothing about any screen changes. Do not change how any screen looks or behaves otherwise.
3. Use the demo's own objects (the queue "Neon reread", its collection, the works A82 names).
   Where A82 says **no demo data** (`seriespreserve`, `revokedevice`, `backupimport`), seed what is
   needed in the DEBUG demo if that is a few lines; otherwise say why not.
4. Where Android shows a screen inline rather than as its own page (`languagepicker`, `tagpicker`,
   `bulknames`, …), open the nearest Android equivalent with that part showing (expanded, focused
   or scrolled into view) and say what is shown.
5. One JVM test: every name in A82 is known to the dispatcher. No other tests.

Result: a table `name | what is on screen | file:line | notes`, then what you could not do and why.
