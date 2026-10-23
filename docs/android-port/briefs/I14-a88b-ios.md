# Brief I14 (iOS): the iPhone's side of A88b

Worktree `/Users/cidy02/kudos-agent-ios`, branch `claude/agent-ios-i14` (from your I13 record). Same rules:
compile iOS (arm64 simulator) and macOS with your own derivedDataPath; no tests, no simulator, no commits,
no sign-in, no AO3; SwiftLint at HEAD's level. Write `docs/android-port/briefs/I14-result.md` with
`path:line`, and message me.

From your A88b note (and Gemini's when it lands, which I'll forward if it adds anything):
1. `colsfilter` at AX5: "Unrevealed" shows through the top of the pinned Reset button (your I10 gradient).
   Opaque up to the button, fading only above it.
2. `colitems`: the footer cuts the creator to "AO3_Reader…". Show it whole.
3. `parentpicker` at AX5: the URL gets a system hyphen when it wraps. A URL must not hyphenate (no hyphens
   added at wrap points; it may still wrap).
4. The shot routes that miss their page at AX5: `chsettingsedit`, `tagset` and `tagseteditor` show the
   collection page (the row they push from is below the fold, so its `.task`/take never runs). Make each
   open its page at every text size (`App/DemoLibrary.swift` `DebugShots`, DEBUG only), e.g. by pushing
   from the page's own appearance rather than a row's, or presenting directly.
