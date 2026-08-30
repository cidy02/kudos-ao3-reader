Checklist 1–3 completed.

Findings:

1. Required regression missing: §7 requires `f(x) (Band)`, but it has no test assertion. Add `title == "f(x)"`, `qualifier == "(Band)"`. [Plan](/Users/cidy02/kudos-tts-kokoro/discussions/fandom-name-disambiguation.md:305)

2. The live test diff changed after review began: six assertions at [FandomDisplayNameTests.swift](/Users/cidy02/kudos-tts-kokoro/KudosTests/FandomDisplayNameTests.swift:329) are absent from the saved patch. They look correct, but the earlier green gate does not cover them; §8 requires a fresh three-review sign-off for test-assertion changes. [Gate rule](/Users/cidy02/kudos-tts-kokoro/discussions/fandom-name-disambiguation.md:371)

Control flow is otherwise sound: the rules array preserves `A → C → D → bracket → dash → B`, six one-shot entries, six-pass bound, shared nonempty-head guard, and qualifier prepending. `tidied`, `|` handling, and all raw-name identity/search/zoom/query paths remain unchanged. [Implementation](/Users/cidy02/kudos-tts-kokoro/kudos-ao3-reader/Features/Search/FandomListView.swift:252)

I manually inspected all 83 assigned changed rows: all are justified (75 A-only, 6 A+bracket, 2 A+D); no empty or separator-ending titles. `Percy Jackson…`, `Bridgerton…`, and `Jonathan Strange & Mr Norrell…` are correct.

Adversarial source-trace: `Core RPF (TV) & Related Fandoms - All Media Types-Fandom - Creator` → title `Core`; qualifier `RPF (TV) & Related Fandoms - All Media Types - Fandom - Creator`. It exercises all six rules across four passes without re-peeling.

VERDICT: FIX-THEN-SHIP — add the required `f(x) (Band)` regression, freeze the latest diff, rerun the gate, and obtain fresh three-review sign-off.
