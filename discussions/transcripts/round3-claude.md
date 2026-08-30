CLAUDE — ROUND 3, dividing the labour

## 1. Should the implementation be divided? No.

The honest answer is that this is one person's afternoon: six rules in one
~90-line function, a test file, and a validation script. Splitting the
*implementation* four ways would cost more in coordination than it saves in
wall-clock, and it would produce a worse artifact — six rules written in four
voices inside one function, in a codebase whose house style cares about comment
density and consistency.

The owner's constraint does not say "everyone writes code". It says everyone
reviews it. Those are different, and the second is where the four of us are
actually worth having: this session's record is that the review passes found real
defects (Codex found the ordering bug and the trailing " -" debris; Grok found
three factual errors in other agents' plans) while the *analysis* passes mostly
converged. Reviewing is where we disagree usefully.

**Proposal: one writer, three reviewers, and split the validation — which is the
one genuinely parallel piece.**

## 2. If it were divided, the seams are wrong

Per-rule (A/B/C/D/E) is the obvious split and the bad one: all six rules live in
`FandomDisplayName.split`, so four agents would be editing one function. The
merge would be hand-reconciled, which is exactly the situation where an ordering
constraint gets lost — and this change has a load-bearing one (E must precede the
spaced dash or `À Tout le Monde (Set Me Free)` loses its parenthetical). I would
reject a per-rule split for that reason alone.

The seam that does exist is **implementation | adversarial tests | corpus
validation**. Those touch different files and different artefacts.

## 3. Who does what

**Claude writes the implementation and the first test pass.** Not because it is
better at Swift, but because it is the only one of us that can run the build, the
test suite, SwiftLint, the simulator, and git in this repo. Every alternative
routes the code through me anyway to be compiled and committed; making me the
author removes a translation step rather than adding one.

**Grok reviews the rule semantics.** It has been the most accurate on this corpus
— it caught Codex's short D list, Codex's wrong-width bracket binding, and
Gemini's ZWNJ prescription. That is exactly the skill this diff needs.

**Codex reviews the control flow.** It found the fixed-point defect and the
once-only over-strip, which are the two hardest things about this function. It is
also the only agent that has changed its mind under argument here, which is worth
something in a reviewer. Caveat: it hit a usage limit today, so give it the
smallest, most focused brief of the three.

**Gemini writes the adversarial test cases, independently of my tests.** Its
round-1 rule sketches were the most complete, and tests written by someone who
did not write the implementation are worth more than tests written by someone who
did. It should write them from the findings document, not from my diff.

## 4. Tie-breaking and rounds

- **Two review rounds, maximum.** Round 1: three independent reviews. I fix what
  is agreed. Round 2: only the reviewers who raised an unresolved objection look
  again. If it is still contested after that, it goes to the owner with both
  positions stated in one paragraph each — not a transcript.
- **Ties break toward the smaller change.** If two reviewers disagree about
  whether to add something, it does not go in. This is a cosmetic feature; the
  asymmetry between "missing a suffix" and "shipping a rule we argued about" is
  real.
- **Any reviewer can block on evidence, nobody can block on taste.** A reviewer
  saying "this breaks `Sunn O)))`" stops the ship. A reviewer saying "I'd order
  these differently" does not, unless they show a name that changes.
- **Escalate to the owner immediately** — not after two rounds — if a reviewer
  finds a case where the parsed title would leak into identity, search, or the
  works query. That is the one class of defect here that is not cosmetic.

## 5. What review means for THIS change

A reviewer must do all three, and say which they did:

1. **Read the diff** against the verdict's rule table. Specifically check the
   ordering constraint (E before the spaced dash) and that every new rule has a
   once-only flag and a nonempty-stem guard.
2. **Run the corpus diff.** Old `split` vs new over all 144,866 names, and look
   at the names whose output *changed* — not the counts. The counts have agreed
   while the behaviour was wrong twice already this session.
3. **Write one adversarial input** they believe will break it, and report the
   result whether or not it did. A review that produces no new test case has not
   really been done.

Required assertions in any review sign-off: empty titles still 0; no title still
ends in a separator or `:`; the negative guards still hold (`Sunn O)))`,
`Eason-Related Fandoms`, `Pizza Fandom`, `f(x) (Band)`,
`Ellie and Abbie (and Ellie's Dead Aunt) (2020)`); and `id`/search/query still use
the raw name.

## 6. Splitting the corpus validation — yes, this is the parallel piece

144,866 names is too many to eyeball, but the *changed* set will not be. Split it
by category, three ways, one reviewer each:

- **Grok:** Uncategorized Fandoms (68,271 — the largest, and the messiest; it
  holds the HTML junk and most of the degenerate names)
- **Codex:** Movies + TV Shows + Books & Literature (~39,500 — the densest for
  `All Media Types`, years, and creator tails)
- **Gemini:** the remaining seven categories (~37,000 — where the CJK, PT and ES
  localized forms concentrate)

Each reports: names changed in their slice, how many they judge correct, and
every one they judge wrong, verbatim. I reconcile and re-run the whole corpus
before committing so nothing falls between slices.

DIVISION: Claude writes the implementation and runs the gate; Grok reviews rule
semantics, Codex reviews control flow, Gemini writes independent adversarial
tests; the corpus validation splits three ways by category; two review rounds
max, ties break toward the smaller change, and anything touching identity goes
straight to the owner.
