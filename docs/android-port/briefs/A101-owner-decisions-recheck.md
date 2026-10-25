# A101: are the owner's decisions still all present on Android? (read only)

The owner asked for Android parity's "Done" to be verified before any iPhone Duo work. Part 2 of §0's Done
is: every owner decision Android must reproduce is present on Android. Your A77 (2026-10-22, at Android
`a5a2c7f4`) found 62 present and 10 gaps. Triage, at the foot of `docs/android-port/audits/A77-result.md`:
- **Eight fixed** in `8c80b3b7` (brief 3go).
- **One not a fault:** comment swipe rails. Android uses buttons, by decision.
- **One an open owner question:** Q9, Backup's technical notes.

A lot has landed since: 3gw to 3hd, A96 to A100.

**Read only.** Work in `/Users/cidy02/kudos-agent-codex` on a new branch `android/agent-codex-a101` from the
lane's `7b2f69f4`; create it yourself. Do not change code, commit, push, sign in, contact
archiveofourown.org, or run Gradle. Write only `docs/android-port/audits/A101-result.md`.

1. **Re-check every A77 entry** (W01–W16 and the rest) at `7b2f69f4`: still present, still different, or
   now absent. For each, give the current `path:line` and one line of evidence. Look hardest at the eight
   3go fixes and at anything later commits touched:
   - the download ring and greying;
   - Recently Deleted's "Downloaded work";
   - the shell's newest wash;
   - the Account icons' `accentInk`;
   - the editor switches' picked colour;
   - the short fill;
   - the no-tags explanation.
2. **Owner decisions made after A77** that Android must reproduce:
   - the answered questions in `docs/android-port/OWNER-DECISIONS-ANDROID.md` (each one marked answered);
   - the owner quotes in `docs/android-port/LIVING-PROMPT.md` §0 dated 2026-10-22 or later that concern
     Android;
   - `DECISIONS.md` entries citing the owner after 2026-10-22.
   For each: present or not, with `path:line`. Skip the iPhone-Duo-only decisions (they're iOS's), and
   anything an open owner question keeps waiting.
3. **A table at the top:** present / different / absent / waiting on an owner question, then a ranked list
   of anything not present, with how you'd fix it.

iOS is the reference for what "present" means: `/Users/cidy02/kudos-ios-polish/kudos-ao3-reader/`. Its
working tree has uncommitted iPhone Duo work; read the committed state (`git show HEAD:<path>`) where it
matters.
