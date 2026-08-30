Do not divide the implementation. This is one ordered state machine, not six independent rules: all rules share flags, the loop bound, peel order, cleanup, and qualifier assembly. Per-rule branches would create semantic merge conflicts. Tests should stay with the implementation for the same reason.

1. **Claude** freezes the baseline catalog and runs one canonical old→new report. If that needs a temporary script, Gemini, Grok, and Codex review it too; it stays out of the commit.

2. **Gemini** writes one atomic parser-and-tests patch. Gemini is the sole source author because the rule structure is the core risk.

3. In parallel, the three non-authors review the exact patch:
   - **Codex:** bounded adversarial parser review—§7 ordering, once-only flags, mixed-width brackets, glued RPF/Fandom, cleanup, and scope creep into the scraper artifacts. Supply counterexamples; do not own a long unattended task.
   - **Grok:** catalog-semantic review—validate the literal localized-AMT set and inspect the corpus changes, especially creator/RPF and long-tail results.
   - **Claude:** integration review—confirm raw `fandom.name` remains the identity/filter/zoom/query value; run targeted tests, final gate, simulator/manual Browse check, and make the one commit.

4. **Gemini** makes one consolidated correction. Claude, Grok, and Codex reread the final delta/SHA. Claude then runs `Scripts/verify.sh`, performs the required Movies/TV tap-through check, updates `TASKS.md`, and commits. Claude should not make opportunistic source edits; return them to Gemini so every source change has three reviewers.

Split only the catalog eyeballing. Generate rows using the production input: category, raw fandom name, trimmed last non-empty `|` segment, old split, new split, and rule/cascade label. Do not deduplicate cross-category rows.

- Grok: `Celebrities & Real People`, `Music & Bands`; leads reconciliation of catalog counts.
- Codex: `Movies`, `TV Shows`, `Books & Literature`, `Theater`.
- Claude: `Anime & Manga`, `Cartoons & Comics & Graphic Novels`, `Video Games`, `Other Media`.
- Allocate `Uncategorized Fandoms` by sorted **changed-row** ranges to equalize the three workloads; preserve its category label and record each range.

Every changed row gets one accountable reviewer and a label: expected A/B/C/D/E/cascade, unexpected, or needs owner decision.

Review means more than “LGTM”:

- Read the final source-and-test diff against §7.
- Verify exact order `A → C → D → parenthetical → spaced dash → B`, six one-shot flags / `0..<6`, nonempty tidied stems, prepend qualifier order, and unchanged `tidied`/`|` behavior.
- Check the required real fixtures and negatives, including Related Fandoms, bare `RPF`, `Pizza Fandom`, mixed-width brackets, `Sunn O)))`, smileys, and Ellie/Abbie.
- Pin `Doctor Who (1963)` and `(2005)` to the same display title but distinct raw identities.
- Each reviewer supplies at least one concrete adversarial input/expected result; Gemini incorporates accepted cases and reviewers recheck them.
- Inspect every changed catalog row, record coverage, zero empty titles, and separator-ending-title counts. Any unclassifiable change blocks shipment.
- Claude alone runs the full gate and screenshot-backed UI/tap validation; all three reviewers explicitly sign off on the final source diff.

Use two rounds maximum: one parallel substantive review, then one final-delta review. Evidence from the frozen catalog and §7 resolves factual disputes. Claude may resolve mechanical conformance within §7; any disagreement that changes a rule, accepts a new false-positive tradeoff, or expands scope goes to the human owner. No majority vote and no open-ended third debate.

DIVISION: Gemini writes one cohesive parser-and-tests patch; Grok, Codex, and Claude independently review it while splitting the changed-row catalog audit, and Claude gates and commits after final-diff sign-off.
