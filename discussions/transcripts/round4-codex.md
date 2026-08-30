1. Gemini.

2. Claude may apply only diagnostic-determined, behavior-preserving fixes; anything changing parser behavior, test inputs, or expected outputs returns to Gemini. The mechanical-fix diff is reviewed by all three before commit.

3. Future tie-break: when an independent eligible author can edit the repo, choose the non-gatekeeper as author; otherwise the gatekeeper authors.

AUTHOR: Gemini  
GATE-FIX RULE: Claude may make only diagnostic-determined fixes that preserve behavior, disclose them for three reviews, and return every substantive change to Gemini.
