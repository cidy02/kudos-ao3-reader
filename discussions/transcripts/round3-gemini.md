### 1. Is Dividing the Implementation Correct?

**No.** Manufacturing code-level parallelism across a single ~90-line Swift function (`FandomDisplayName.split`) is an antipattern that invites merge conflicts, flag naming mismatches, and loop-invariant churn. 

The implementation itself must have a **single author**. The work becomes multi-agent where it matters: **independent code review, adversarial test expansion, and sharded full-catalog diff validation.**

---

### 2. The Actual Seams

1. **Authoring (Serial):** Write the 6 rules in `FandomDisplayName.split` and update `FandomDisplayNameTests.swift` per the Section 7 verdict.
2. **Catalog Diff Generation (Serial):** Run the 144,866-name old-vs-new split script to produce the exact changed-names delta.
3. **Diff Shard Validation (Parallel):** Eyeball every changed row across partitioned categories to confirm zero regressions.
4. **Adversarial Review & Test Injection (Parallel):** Review code diff against negative rules and append regression test cases.
5. **Gate Execution & Commit (Serial):** Run `Scripts/verify.sh`, perform simulator check, and commit.

---

### 3. Role Assignment by Strength

* **Gemini (Author / Implementation & Initial Tests):** Produced the clearest structure and complete rule sketches in Rounds 1 & 2. Gemini writes the exact Swift implementation of `FandomDisplayName.split` and updates/adds the core unit tests.
* **Grok (Multilingual & Edge-Case Validator):** Possesses the richest empirical catalog knowledge (caught the mixed-width binding bugs, missing AMT translations, and ZWNJ ingestion traps). Grok owns the CJK/Multilingual and `-Fandom` catalog diff shard review and negative-rule audits.
* **Codex (Adversarial Parser Auditor):** Caught the parser-ordering traps and debris bugs. Codex audits the parsing order, bounds, and scalar trimming logic, and drafts adversarial test cases. *(Given usage limit risks, Codex is assigned bounded, non-blocking async review tasks.)*
* **Claude (Build Gatekeeper & Integrator):** Holds repo context and active build/simulator tooling. Claude runs the harness, partitions the diff, runs `Scripts/verify.sh`, validates the UI on simulator, and commits.

---

### 4. Review Protocol & Deadlock Prevention

* **Maximum 2 Review Rounds:**
  * **Round 1:** Gemini submits the implementation + test diff; Claude posts the 144k catalog diff output. Grok, Codex, and Claude review simultaneously.
  * **Round 2:** Gemini applies fixes for any demonstrated defects. Final sign-off.
* **Ground Rules for Objections:** Reviewers cannot block on preference or aesthetic style. An objection **must provide an empirical counterexample** (a failing fixture from the 144k corpus or a reproducible Swift runtime defect).
* **Tie-Breaking:** 
  1. The Section 7 Verdict is canonical.
  2. If an edge case is unspecified in Section 7, **empirical corpus safety wins** (favor zero false positives over aggressive stripping).
  3. If still tied, **Claude** (as gatekeeper) casts the deciding vote.
* **Human Escalation:** Only escalate if there is a fundamental product disagreement on scope (e.g., whether to re-open sibling collisions / J). Implementation disagreements are settled strictly by empirical test cases.
* **Quorum:** Approval from Claude + Grok (Codex is optional/advisory if throttled by usage limits).

---

### 5. Review Checklist for this Change

Every reviewer must verify:

- [ ] **Loop & Flags:** Loop bound is `0 ..< 6` (no off-by-one); each rule uses its dedicated `took*` guard; loop breaks cleanly when `title == before`.
- [ ] **Exact Rule Order:** 
  1. `& Related Fandoms` (case-insensitive, terminal, last match only).
  2. `RPF` (terminal, case-insensitive, nonempty tidied stem).
  3. `All Media Types` (extended 6-item multilingual literal list).
  4. `lastIndex` Parenthetical (max of ASCII `(` and fullwidth `（`, terminal `)` or `）`).
  5. Spaced dashes (`" - "`, `" – "`, `" — "`, `" ‐ "`).
  6. Glued `-Fandom` (terminal `Fandom`, preceding char in `-–—‐`, nonempty stem).
- [ ] **Negative Guards Intact:** `Spirou & Fantasio`, `Eason-Related Fandoms`, `Sunn O)))`, `MYSTERIOUS MURDER DIY :)`, `f(x) (Band)`, `Ellie and Abbie (and Ellie's Dead Aunt) (2020)`, `Pizza Fandom`, `《...》`, `【...】`, `-Subtitle-` remain unstripped.
- [ ] **Test Refactor:** `Sherlock Holmes & Related Fandoms` is removed from `aPlainNameHasNoQualifier` and given an explicit disambiguation test.
- [ ] **Corpus Invariants (144,866 rows):**
  - **0** empty titles.
  - **0** titles ending in dangling separators (`-`, `–`, `—`, `‐`, `:`, `&`).
  - Total changed names align with expectation (~350–450 names across A–E).
- [ ] **No Scope Creep:** No regex, no new entry types, no caching schema changes, raw `fandom.name` remains identity.

---

### 6. Catalog Diff Sharding Plan

The old vs. new split script will yield ~350–500 changed names. The review of these diffs is partitioned as follows:

* **Shard 1: CJK & Multilingual (~100 names) → Grok**
  * All Chinese, Japanese, Korean parentheticals, fullwidth/mixed-width brackets, and localized AMT (`所有媒体类型`, `Todos os Tipos de Mídia`, etc.).
* **Shard 2: Glued `-Fandom` & RPF (~250 names) → Codex (with Gemini fallback)**
  * Glued `-Fandom` rows, `hetamyuRPF`, unspaced RPF tails, and stem validation.
* **Shard 3: `& Related Fandoms` & High-Volume Media Categories (~100 names) → Claude**
  * Series ampersands vs. disambiguation ampersands, Books/TV/Movies categories, and trailing dash residuals.

---

### Concrete Workflow & Execution Order

1. **Step 1 (Gemini):** Write the Swift code for `FandomDisplayName.split` and updated test fixtures in `FandomDisplayNameTests.swift`.
2. **Step 2 (Claude):** Pull code, run unit tests, and generate the 144k corpus diff artifact.
3. **Step 3 (All - Parallel):** Grok, Codex, and Claude execute their checklist and review their assigned catalog diff shards.
4. **Step 4 (Gemini / Claude):** Patch any surfaced edge cases (Max 1 revision).
5. **Step 5 (Claude):** Run `Scripts/verify.sh`, verify simulator Browse interaction, and commit.

---

DIVISION: Gemini implements the single-function parser and unit tests, Claude runs the harness and build gate, Grok and Codex audit the logic and shard-validate the 144k catalog diff, with Claude breaking ties.
