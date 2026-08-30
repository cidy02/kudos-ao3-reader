1. J — Changed my mind: defer it. Full-category counting removes filter flicker, but not the unvalidated conditional typography or load-time projection cost. The supplied catalog’s largest category is actually 68,271 rows, not 14k. If revisited, start with a screenshot-gated uniform contrast tweak; only then consider a full-category collision `Set`, not entries.

2. Placement — Changed my mind: without J, precomputed `FandomListEntry`s have no independent case. Keep parsing lazy in `FandomListRow`, but use local `let` bindings in `body` so primary-name splitting and `split` run once per body evaluation. Do not cache in `init`.

3. D — Agree: ship it. Use the six exact terminal literals: English plus `所有媒体类型`, `所有媒體類型`, `所有媒體型別`, `Todos os Tipos de Mídia`, and `Todos los tipos de medios`. The catalog has 20 localized matches.

Ship plan:

- Preserve raw `fandom.name` as ID, filter text, zoom key, and query payload; parse only the last `|` segment for presentation.
- Keep the once-only loop, expand to six passes with distinct flags. Final order:

  `C RPF → D All Media Types → A Related Fandoms → E mixed-width brackets → existing spaced dash → B terminal dash-Fandom`

  The bounded re-pass handles reverse nesting; qualifiers still insert at the front.
- A must require the leading space: `" & Related Fandoms"` / `" and Related Fandoms"`.
- C is terminal, case-insensitive `RPF`, with a nonempty-head guard.
- E accepts either terminal close and chooses the globally last `(` or `（`.
- B remains an allow-listed terminal `Fandom` rule with optional adjacent whitespace around observed dash forms; run it after the generic spaced dash. No broad dash heuristic or exception list.
- Add real-tag positives, stacking cases, and negative guards; run the corpus audit and visual check. Keep F–I as a separate `AO3Client.parseFandomIndex` task.

Corrections to plans: 14k is not the largest category (Uncategorized is 68,271); 144,866 is the all-category total. Claude’s initializer cache is not durable under SwiftUI recreation. Gemini’s A matcher lacks a leading space, its glued-RPF fallback misses lowercase `rpf`, and its D list omits PT/ES. Any future blanket ZWNJ stripping would corrupt legitimate names.

CONSENSUS: yes
