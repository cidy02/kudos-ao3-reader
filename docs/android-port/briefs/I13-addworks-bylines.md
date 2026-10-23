# Brief I13 (iOS): Add Works' bylines at the largest text

Worktree `/Users/cidy02/kudos-agent-ios`, branch `claude/agent-ios-i13` (from `7d58eebd`, Codex's I12 as
written; polish has the same plus two small A91 fixes elsewhere). Compile iOS (arm64 simulator) and macOS
with your own derivedDataPath; no tests, no simulator, no commits, no sign-in, no AO3; SwiftLint at HEAD's
level. Write `docs/android-port/briefs/I13-result.md` with `path:line`, and message me.

Both reviewers of A88a (Gemini and you) found, in `/Users/cidy02/kudos-tools/pairs/tiles-a88/addworks.png`'s
largest column: the iPhone's first byline breaks mid-word and ends in "…" ("by un- / cle_iroh…") where
Android shows "uncle_iroh_fan" whole. I9 lifted the title's line limit and made the byline non-compact at
the accessibility sizes (`Features/Library/AddLibraryWorksSheet.swift`), but the byline still cuts. Show it
whole at every size (wrap at word boundaries, no ellipsis), as the app's other work rows do at the
accessibility sizes. Check I12's new heading and count in the same file still read right. Note: these
shots predate I12, which I'll re-shoot with your change.
