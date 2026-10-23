# Brief I16 (iOS): what A88c found on the iPhone

**Write code in `/Users/cidy02/kudos-agent-ios` only, on a new branch `claude/agent-ios-i16` from
`bd533264` (the polish branch's tip; I15's `URLTextField` lands separately and touches other files). Do not
commit to the polish branch, push, sign in, contact archiveofourown.org, boot a simulator, or run
xcodebuild (Claude builds, tests and shoots; the Android emulator is in use).** Write
`docs/android-port/briefs/I16-result.md` first; per item `path:line`, what changed, and per test what it
does with its change reverted. Android (`/Users/cidy02/kudos-android-lane/android/`) shows what the other
side looks like; the tiles are `/Users/cidy02/kudos-tools/pairs/tiles-a88c/<name>.png` and raw shots
`/Users/cidy02/kudos-tools/pairs/shots/i_<name>_<column>.png`.

1. **`readerspeech` at AX5**: the Sample Text picker's value is cut in the middle to "Plain…rration" by the
   system menu picker (`Features/ReaderReadium/ReaderSpeechAuditionHarness.swift:133-138`). The same
   section is on Settings › Listening, with the same cut. Android puts the value under its label at the
   largest sizes, whole. Keep the value whole at accessibility sizes.
2. **The current speed's pill is nearly invisible** in Light and Sepia: "1.0x (default)" is near-white text
   on a pale glass fill (`ReaderSpeechAuditionHarness.swift:87-90`, `.buttonStyle(.bordered)` with
   `.disabled(...)` for the current rate; see `/Users/cidy02/kudos-tools/pairs/shots/i_readerspeech_light.png`
   and `_sepia.png`). Gemini found it; Claude confirmed it in the shots. Android draws the current one as
   grey text on a light fill, readable in every theme. Make the current speed readable in all four themes
   while it stays non-tappable and VoiceOver still says it's the current/dimmed one.
3. **Capture: the AX5 `pronunciations` and `pronunciationedit` shots stay on Settings › Listening** (shot at
   10:02 and 10:04 today); the Light column now opens Pronunciations. Find why the DEBUG shot route doesn't
   get past Listening at AX5 (`App/DemoLibrary.swift` `DebugShots`, and the Listening page's route to
   Pronunciations) and fix the route, not the page.

Tests (Swift Testing, as the suite's other files) for every behaviour change, each failing with its change
reverted; say which suites to run.
