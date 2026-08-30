=== grok delegate result ===
mode:    write-capable
stop:    end_turn
session: 01a052fa-d86f-7e12-b830-2a34d692758d

I'll read the agreed verdict, the function, and the tests first so the labour split matches the actual work, not a four-person fiction.**Do not divide the implementation.** One agent writes the function and the tests; the other three review. Manufacturing a four-way split of a ~90-line function is how you get a merge disaster, not a faster ship.

The work is: six ordered rules in one loop, flags, bound `0..<6`, existing `tidied`, existing tests to extend, one throwaway catalog diff. Section 7 already specifies order, needles, and negative guards. That is one sitting for someone who already has the file open.

---

### 1. Divide implementation? No.

Per-rule ownership of A/B/C/D/E is rejected. The rules are not independent: E must stay before the spaced dash, B after it, RPF must be able to fire after a dash peel, flags stop a second bracket eating a title parenthetical. Four agents in `FandomDisplayName.split` will fight over the same 90 lines and the same flags.

Implementation-vs-tests is also not worth a handoff. The fixtures are already listed in the verdict. Tests and code belong in the **one commit** the verdict requires.

The only real parallel work is **review + catalog eyeballing**, and it starts after the commit exists as a diff.

---

### 2. Actual seams

| Seam | Verdict |
|---|---|
| Per-rule in `split` | Reject. Loop-order coupling. |
| Impl vs tests vs harness | Reject as a labour split. Sequential, one author. |
| Catalog eyeball of *changed* names | **Yes — split by which rule fired**, not by media category. Category slices mix rules and hide systematic mistakes. |

---

### 3. Who does what

**Claude writes and ships.** Repo context, `verify.sh`, simulator, commit. Gemini’s sketches are already frozen in §7; transcribing them is not a second architecture job. Codex is unreliable for unattended work (usage limit today). Grok’s value is catching factual errors in other people’s output — that is a reviewer role.

| Who | Task |
|---|---|
| **Claude** | Implement A–E in `FandomDisplayName.split` exactly as §7. Extend `FandomDisplayNameTests` (A–E fixtures, rewrite `aPlainNameHasNoQualifier`, pin `Doctor Who (1963)`/`(2005)` sharing a display title with raw-name identity). Throwaway old-vs-new catalog script; emit a diff **grouped by rule that fired**, plus an `other` bucket. Run `Scripts/verify.sh`. Manual Browse pass. Commit. Update `TASKS.md` (F–I follow-up, J deferred). |
| **Gemini** | Structure review: loop order, flags, bound `0..<6`, E-before-dash, B-after-dash, last-match A, later-of-two-openers E. Adversarial tests vs the negative-guard list. Eyeball **D + E** catalog rows. |
| **Grok** | Catalogue/factual review: needles, last-match A (`Spirou & Fantasio`), leading-space A (`Eason-Related Fandoms`, `Chinese Related Fandoms`), glued-B dash set including `x -Fandom` / `x- Fandom`, D list completeness (CJK + PT + ES, no extras). Eyeball **A + B** (the bulk, ~260 names). |
| **Codex** | Parser-order / defect review — short and bounded, so a usage-limit death is cheap: once-only flags, debris, empty-title invariant, glued RPF nonempty-stem, mixed-width E not binding the wrong opener. Eyeball **C + the entire `other` bucket**. If `other` is large, halt; the implementation did extra work. |

Claude does **not** mark their own catalog rows as reviewed.

---

### 4. Review without deadlock

Reviewers check **fidelity to §7**, not a new plan. Re-opening J, F–I, dash-residual, or parsing location is out of scope; that goes to the human immediately, it is not a review comment.

- **Hard veto (any one reviewer):** verdict miss, empty title, identity used as a key, a false peel in the catalog, unexpected `other` churn.
- **Not a veto:** taste, deferred items, “I would have ordered the flags differently” when the order matches the table.
- **Tie-break on judgment calls:** the **human owner**. Agents do not majority-vote product. On “does this line match §7?” Claude re-reads §7 and fixes if it doesn’t; if two readings of §7 exist, escalate.
- **Rounds:** **one review + one fix-up, then ship.** A third round means we are re-litigating. Escalate.
- **Availability:** all three are *asked*. Ship when **2 of 3 have approved** and no hard veto is outstanding. If Codex is usage-capped, Gemini+Grok is enough — that is why Codex’s slice is short.

---

### 5. Review checklist (this change)

Every reviewer, before saying yes:

1. Diff `split` against the §7 table: order 1–6, flags, bound `0..<6`, insert-at-0, `tidied` untouched.
2. A: both needles, case-insensitive, **terminal**, **last** match, leading space (no `Eason-Related Fandoms`).
3. C: terminal `RPF` including glued; nonempty tidied stem; bare `RPF` stays whole.
4. D: exactly the six literals; no speculative translations.
5. E: **before** spaced dash; any terminal `)` / `）`; opener = **later** of `lastIndex("(")` and `lastIndex("（")` — not a pair list.
6. B: **after** spaced dash; terminal `Fandom`; last char in `-–—‐`; does not peel `Pizza Fandom`.
7. Identity: `onSelect`, filter, zoom key still use raw `fandom.name`. Parsed title is never a key. Pin `Doctor Who (1963)` vs `(2005)`.
8. Scope: no new files, no regex, no `pbxproj`, no `SearchView`, no J, no F–I, no Unicode-format stripping.
9. Tests: `Sherlock Holmes & Related Fandoms` is **not** a plain-name fixture; negatives present (`Spirou…`, `Eason-Related…`, `Sunn O)))`, `:)` , `f(x) (Band)`, Ellie/Abbie, `Pizza Fandom`).
10. Catalog: empty titles stay 0; no new titles ending in a separator; every changed name is in a rule bucket or `other`; `other` is empty or each row is explained.

Assigned extras (do not all three do all three jobs):

- **Gemini:** write or demand any missing adversarial test from item 9.
- **Grok:** sample the catalog diff against the known counts (~80 A, ~180 B, ~49 C, ~8–21 D, ~16–23 E). Material under/over-count is a veto.
- **Codex:** walk one compound that hits multiple rules (e.g. glued RPF after a dash peel) and confirm the loop is a fixed point without eating a title parenthetical.

Reading the diff alone is not review. Skipping the catalog diff is not review. Dumping a new rule proposal is not review.

---

### 6. Catalog eyeball — yes, split

Expected churn is hundreds, not 144k (A–E are ~350–450 names plus a hopefully empty `other`). Split **by firing rule**:

- Grok: A + B
- Gemini: D + E
- Codex: C + `other`

If `other` is more than a handful, stop and re-open the implementation, do not divide it further. Record coverage / empty-title / trailing-separator counts in the commit body as §7 requires. No 144k sweep in CI.

---

### Order

1. Claude implements + tests + grouped catalog diff (no parallel authors).
2. Gemini, Grok, Codex review in parallel on the checklist and their eyeball slices.
3. Claude does one fix-up if anything is a hard miss.
4. Claude runs `verify.sh`, Browse pass, commits, updates `TASKS.md`.
5. Human only if a §7 ambiguity or a deferred-item fight appears.

**DIVISION: Claude writes the whole parser+tests+diff in one commit; Gemini/Grok/Codex review in parallel (structure / catalogue / ordering) and split the changed-name eyeball by rule; one fix-up then ship.**

Continue this thread: grok -c   (in the same directory)
