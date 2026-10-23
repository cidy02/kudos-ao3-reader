# Brief I15 (iOS): the parent work's URL still hyphenates at AX5

Worktree `/Users/cidy02/kudos-agent-ios`, branch `claude/agent-ios-i15` (from polish `bd533264`, which has your
I14 as T-439). Same rules: compile iOS and macOS, no tests, no simulator, no commits, no AO3. Write
`docs/android-port/briefs/I15-result.md` and message me.

The AX5 re-shoot (`/Users/cidy02/kudos-tools/pairs/shots/i_parentpicker_big.png`, taken on integrate with
T-439) still shows the URL field broken as "https:// / archiveo- / fourown.org/ / works/1": the `zxx`
typesetting language did not stop the TextField's hyphenation. Use the fallback you named (a representable
with hyphenation off), or another way that wraps the URL at any point without inserting hyphens. Keep the
field's behaviour from T-435/I10: line breaks dropped, Return ends editing, 1–4 lines, URL keyboard.
